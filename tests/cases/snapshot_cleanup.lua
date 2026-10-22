fixture.setup()

local api = require("sess.api")
local editor = require("sess.editor")
local state = require("sess.state")
local storage = require("sess.storage")

local project = fixture.directory("target")
local ok, err, target = api.session.create(project)
assert(ok, err)
local filename = project .. "/saved.txt"
vim.fn.writefile({ "saved content" }, filename)
vim.cmd.edit(filename)
assert(api.session.save())

local outgoing
ok, err, outgoing = api.session.create(fixture.directory("outgoing"))
assert(ok, err)
local live_buffer = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(live_buffer, 0, -1, false, { "keep this edit" })
state.set_view(target.id, nil) -- exercise persisted sourcing, not the live view
local snapshot = assert(storage.read_session(target.id))

-- Plugins may remove the empty starting buffer while the generated snapshot
-- opens its files. Its final s:wipebuf cleanup must tolerate an absent buffer.
local placeholder
local cleanup_autocmd = vim.api.nvim_create_autocmd("BufLeave", {
    callback = function(event)
        if
            event.buf ~= live_buffer
            and vim.api.nvim_buf_get_name(event.buf) == ""
            and not vim.bo[event.buf].modified
        then
            placeholder = event.buf
            vim.bo[placeholder].bufhidden = "wipe"
        end
    end,
})
local load_post = false
vim.api.nvim_create_autocmd("SessionLoadPost", {
    once = true,
    callback = function()
        load_post = true
    end,
})

ok, err = api.session.load(target)
vim.api.nvim_del_autocmd(cleanup_autocmd)
assert(ok, err)
assert(placeholder and not vim.api.nvim_buf_is_valid(placeholder))
assert(load_post, "snapshot execution must continue after placeholder cleanup")
fixture.equal(target.id, api.state.current().id)
fixture.equal(outgoing.id, api.state.prev().id)
fixture.equal(filename, vim.api.nvim_buf_get_name(0))
fixture.equal({ "saved content" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))
fixture.equal(project, vim.fn.getcwd())
fixture.equal(assert(storage.get_session_path(target.id)), vim.v.this_session)
fixture.equal(snapshot, storage.read_session(target.id))
assert(vim.api.nvim_buf_is_valid(live_buffer))
fixture.equal({ "keep this edit" }, vim.api.nvim_buf_get_lines(live_buffer, 0, -1, false))

-- Do not suppress unrelated snapshot errors or mark failed execution as loaded.
local previous = vim.v.this_session
local sourced, source_error =
    pcall(editor.source_snapshot, "/tmp/broken.vim", "throw 'snapshot failure'")
assert(not sourced and tostring(source_error):match("snapshot failure"), tostring(source_error))
fixture.equal(previous, vim.v.this_session)

-- E517 outside the generated placeholder cleanup is still a real failure.
sourced, source_error = pcall(editor.source_snapshot, "/tmp/broken.vim", "bwipe 2147483000")
assert(not sourced and tostring(source_error):match("E517"), tostring(source_error))
fixture.equal(previous, vim.v.this_session)
