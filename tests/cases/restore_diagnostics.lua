fixture.setup()

local editor = require("sess.editor")
local view = editor.capture()
local set_width = vim.api.nvim_win_set_width
vim.api.nvim_win_set_width = function()
    error("injected width failure")
end

local diagnostics = editor.restore(view)
vim.api.nvim_win_set_width = set_width

assert(#diagnostics == 1, vim.inspect(diagnostics))
assert(diagnostics[1]:match("failed to restore window"), diagnostics[1])
assert(diagnostics[1]:match("injected width failure"), diagnostics[1])
