fixture.setup()

local editor = require("sess.editor")

-- A session snapshot contains normal-mode commands. A transition can be
-- invoked directly from terminal mode, so leave that mode before sourcing it.
local get_mode = vim.api.nvim_get_mode
local feedkeys = vim.api.nvim_feedkeys
local exec = vim.api.nvim_exec
local mode = "t"
local executed_in

vim.api.nvim_get_mode = function()
    return { mode = mode }
end
vim.api.nvim_feedkeys = function()
    mode = "n"
end
vim.api.nvim_exec = function()
    executed_in = mode
end

local ok, err = editor.source_snapshot("/tmp/session.vim", "normal! gg")

vim.api.nvim_get_mode = get_mode
vim.api.nvim_feedkeys = feedkeys
vim.api.nvim_exec = exec

assert(ok, err)
fixture.equal("n", executed_in)
