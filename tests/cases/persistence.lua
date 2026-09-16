fixture.setup("store space | percent% # ' quote")

local storage = require("sess.storage")
local api = require("sess.api")

local cwd = fixture.directory("project space | percent% # ' quote")
local ok, err, item = api.session.create(cwd, { name = "special" })
assert(ok, err)

local path = assert(storage.get_session_path(item.id))
fixture.equal(path, vim.v.this_session)

local original = assert(storage.read_session(item.id))
local previous = vim.v.this_session
local command = vim.cmd
vim.cmd = function(args)
    if type(args) == "table" and args.cmd == "mksession" then
        vim.fn.writefile({ "partial snapshot" }, args.args[1])
        error("injected generation failure")
    end

    return command(args)
end

local saved, save_err = api.session.save()
vim.cmd = command
assert(not saved and save_err:match("injected generation failure"), tostring(save_err))
fixture.equal(original, storage.read_session(item.id))
fixture.equal(previous, vim.v.this_session)

local rename = vim.uv.fs_rename
vim.uv.fs_rename = function(from, to)
    if to == path then
        return nil, "injected rename failure"
    end

    return rename(from, to)
end

saved, save_err = api.session.save()
vim.uv.fs_rename = rename
assert(not saved and save_err:match("injected rename failure"), tostring(save_err))
fixture.equal(original, storage.read_session(item.id))
fixture.equal(previous, vim.v.this_session)

for _, name in ipairs(vim.fn.readdir(vim.fs.dirname(path))) do
    assert(not name:match("%.tmp%-"), "leaked temporary file: " .. name)
end

assert(api.session.save())
assert(api.session.unload())
require("sess.state").set_view(item.id, nil) -- exercise persisted sourcing, not the live view
vim.fn.chdir(fixture.root)
assert(api.session.load(item))
fixture.equal(cwd, vim.fn.getcwd())
fixture.equal(path, vim.v.this_session)

-- Session directories remain private (0700), independent of umask.
fixture.equal(448, bit.band(vim.uv.fs_stat(vim.fs.dirname(path)).mode, 511))
