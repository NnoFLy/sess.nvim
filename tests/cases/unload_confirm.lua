fixture.setup()

local api = require("sess.api")
local editor = require("sess.editor")
local storage = require("sess.storage")
local unload_ui = require("sess.ui.unload")
vim.notify = function() end
vim.o.hidden = true

local _, _, a = api.session.create(fixture.directory("a"))
local named = vim.api.nvim_get_current_buf()
local path = a.metadata.cwd .. "/named.txt"
vim.fn.writefile({ "on disk" }, path)
vim.cmd.edit(path)
vim.api.nvim_buf_set_lines(named, 0, -1, false, { "new contents" })
local unnamed = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(unnamed, 0, -1, false, { "unnamed contents" })
vim.cmd("enew")
local terminal = vim.api.nvim_get_current_buf()
local job = vim.fn.jobstart({ "sh", "-c", "sleep 60" }, { term = true })
local unrelated = vim.fn.jobstart({ "sh", "-c", "sleep 60" })
assert(job > 0 and unrelated > 0)

local original = editor.capture()
local snapshot = assert(storage.read_session(a.id))
local function intact()
    fixture.equal(a.id, api.state.current().id)
    fixture.equal(original, editor.capture())
    fixture.equal(snapshot, storage.read_session(a.id))
    fixture.equal({ "on disk" }, vim.fn.readfile(path))
    fixture.equal(-1, vim.fn.jobwait({ job }, 0)[1])
    assert(vim.api.nvim_buf_is_valid(named) and vim.bo[named].modified)
end

vim.fn.confirm = function()
    error("core must not prompt")
end
local ok, err = api.session.unload()
assert(not ok and err:match("confirmation required"))
assert(not api.session.unload(a, { confirm = true }))
intact()

local prompts, answers, index
local function choices(values)
    prompts, answers, index = {}, values, 0
    vim.fn.confirm = function(message, buttons, default)
        index = index + 1
        assert(answers[index], "unexpected confirmation: " .. message)
        table.insert(prompts, buttons)
        if index == 1 then
            fixture.equal("&Save\n&Discard\n&Cancel", buttons)
            fixture.equal(3, default)
        else
            fixture.equal("&Stop\n&Cancel", buttons)
            fixture.equal(2, default)
        end
        -- No write, snapshot or job stop before all confirmations are gathered.
        intact()
        return answers[index]
    end
end

choices({ 3 })
require("sess.ui.command").setup()
vim.cmd("Sess unload " .. a.id)
fixture.equal(1, #prompts)
intact()

choices({ 2, 2 })
ok, err = unload_ui(a.id)
assert(not ok and err == "unload cancelled")
fixture.equal(2, #prompts)
intact()

local save_path = a.metadata.cwd .. "/new | let g:sess_injected = 1.txt"
vim.fn.input = function(options)
    fixture.equal("file", options.completion)
    return save_path
end
choices({ 1, 2 })
ok, err = unload_ui(a.id)
assert(not ok and err == "unload cancelled")
fixture.equal(0, vim.fn.filereadable(save_path))
intact()

-- Cancelling the unnamed buffer's save path also cancels unload.
choices({ 1 })
vim.fn.input = function()
    return ""
end
ok, err = unload_ui(a.id)
assert(not ok and err == "unload cancelled")
fixture.equal(1, #prompts)
intact()

vim.fn.input = function()
    return save_path
end
choices({ 1, 1 })
ok, err = unload_ui(a.id)
assert(ok, err)
fixture.equal(2, #prompts)
fixture.equal({ "new contents" }, vim.fn.readfile(path))
fixture.equal({ "unnamed contents" }, vim.fn.readfile(save_path))
fixture.equal(nil, vim.g.sess_injected)
for _, buf in ipairs({ named, unnamed, terminal }) do
    assert(not vim.api.nvim_buf_is_valid(buf))
end
assert(vim.fn.jobwait({ job }, 3000)[1] ~= -1)
fixture.equal(-1, vim.fn.jobwait({ unrelated }, 0)[1])
vim.fn.jobstop(unrelated)
fixture.equal(nil, api.state.current())
assert(storage.read_session(a.id))

-- Saving a readonly buffer fails before deletion or process termination.
local _, _, b = api.session.create(fixture.directory("b"))
local readonly = vim.api.nvim_get_current_buf()
local readonly_path = b.metadata.cwd .. "/readonly.txt"
vim.api.nvim_buf_set_name(readonly, readonly_path)
vim.api.nvim_buf_set_lines(readonly, 0, -1, false, { "keep me" })
vim.bo[readonly].readonly = true
vim.cmd("enew")
terminal = vim.api.nvim_get_current_buf()
job = vim.fn.jobstart({ "sh", "-c", "sleep 60" }, { term = true })
local seen = {}
vim.fn.confirm = function(_, buttons)
    table.insert(seen, buttons)
    return 1
end
ok, err = unload_ui(b.id)
assert(not ok and err:match("failed to save buffer"))
fixture.equal(2, #seen)
fixture.equal(b.id, api.state.current().id)
assert(vim.api.nvim_buf_is_valid(readonly) and vim.bo[readonly].modified)
assert(vim.api.nvim_buf_is_valid(terminal))
fixture.equal(-1, vim.fn.jobwait({ job }, 0)[1])

-- Discard authorizes buffer deletion, not a file write.
vim.fn.confirm = function(_, buttons)
    return buttons:match("Discard") and 2 or 1
end
assert(unload_ui(b.id))
fixture.equal(0, vim.fn.filereadable(readonly_path))
assert(not vim.api.nvim_buf_is_valid(readonly))
assert(vim.fn.jobwait({ job }, 3000)[1] ~= -1)
