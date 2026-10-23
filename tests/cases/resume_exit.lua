local function launch(options, body)
    return fixture.startup([[
local root = vim.env.SESS_TEST_ROOT
local messages = {}
assert(require("sess").setup({
    store_path = root .. "/store", smart_auto_load = "none", tabline = { enabled = false },
]] .. options .. [[
}))
local api = require("sess.api")
vim.api.nvim_create_autocmd("VimEnter", { callback = function() vim.schedule(function()
    check(function()
]] .. body .. [[
    end)
end) end })
]])
end

local path = fixture.root .. "/store/resume.json"
local function bytes()
    return table.concat(vim.fn.readfile(path), "\n")
end
local function record()
    return vim.json.decode(bytes())
end
launch(
    "auto_save = true,",
    [[
local dir = root .. "/a"
vim.fn.mkdir(dir, "p")
assert(api.session.create(dir, { id = "a" }))
vim.fn.writefile({ "saved contents" }, dir .. "/file.txt")
vim.cmd.edit(dir .. "/file.txt")
]]
)
fixture.equal({ "a" }, record().active_ids)
local previous = bytes()

-- Required save failure preserves history and must be visible during real exit.
local failure = launch(
    "auto_save = true,",
    [[
assert(api.session.load("a"))
local rename = vim.uv.fs_rename
vim.uv.fs_rename = function(from, to)
    if to:match("session.vim$") then return nil, "injected exit save failure" end
    return rename(from, to)
end
]]
)
fixture.equal(previous, bytes())
assert(failure.stderr:find("injected exit save failure", 1, true), failure.stderr)

local write_failure = launch(
    "auto_save = false,",
    [[
assert(api.session.load("a"))
local rename = vim.uv.fs_rename
vim.uv.fs_rename = function(from, to)
    if to:match("resume.json$") then return nil, "injected resume write failure" end
    return rename(from, to)
end
]]
)
fixture.equal(previous, bytes())
assert(write_failure.stderr:find("injected resume write failure", 1, true), write_failure.stderr)

-- A never-managed one-off edit leaves the record byte-for-byte untouched.
launch(
    "auto_save = true,",
    [[
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unrelated" })
]]
)
fixture.equal(previous, bytes())

-- Bookkeeping does not force snapshots when autosave is disabled or excluded.
for _, options in ipairs({
    "auto_save = false,",
    'auto_save = true, exclude_filetypes = { "skip" },',
}) do
    launch(
        options,
        [[
assert(api.session.load("a"))
local dir = root .. "/unsaved"
vim.fn.mkdir(dir, "p")
vim.fn.writefile({ "unsaved editor context" }, dir .. "/other.txt")
vim.cmd.edit(dir .. "/other.txt")
vim.bo.filetype = "skip"
]]
    )
    fixture.equal({ "a" }, record().active_ids)
    launch(
        "auto_save = false,",
        [[
assert(api.session.load("a"))
assert(vim.api.nvim_buf_get_name(0):match("/a/file.txt$"))
]]
    )
end

-- Intentionally unloading the last session publishes an empty set.
launch(
    "auto_save = false,",
    [[
assert(api.session.load("a"))
assert(api.session.unload())
]]
)
fixture.equal({}, record().active_ids)
assert(record().current_id == nil)

-- A committed snapshot with a metadata warning still publishes and exposes the
-- warning on real exit. UI observers must not run for a successful code-0 exit.
local warning = launch(
    "auto_save = true, hooks = { after_operation = function(event) if event.operation == 'save' then error('exit observer must not run') end end },",
    [[
assert(api.session.load("a"))
local rename = vim.uv.fs_rename
vim.uv.fs_rename = function(from, to)
    if to:match("metadata.json$") then return nil, "exit metadata warning" end
    return rename(from, to)
end
]]
)
fixture.equal({ "a" }, record().active_ids)
assert(warning.stderr:find("exit metadata warning", 1, true), warning.stderr)
assert(not warning.stderr:find("exit observer must not run", 1, true), warning.stderr)

local before_warning_failure = bytes()
local warning_failure = launch(
    "auto_save = true,",
    [[
assert(api.session.load("a"))
local rename = vim.uv.fs_rename
vim.uv.fs_rename = function(from, to)
    if to:match("metadata.json$") then return nil, "retained exit warning" end
    if to:match("resume.json$") then return nil, "publication failed after save" end
    return rename(from, to)
end
]]
)
fixture.equal(before_warning_failure, bytes())
assert(warning_failure.stderr:find("retained exit warning", 1, true), warning_failure.stderr)
assert(
    warning_failure.stderr:find("publication failed after save", 1, true),
    warning_failure.stderr
)
