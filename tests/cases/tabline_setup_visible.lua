vim.o.tabline = ""
vim.o.showtabline = 2
assert(require("sess").setup({
    store_path = fixture.root .. "/store",
    smart_auto_load = "none",
    auto_save = false,
    tabline = { enabled = true },
}))
assert(vim.o.tabline ~= "")
fixture.equal(2, vim.o.showtabline)
local rendered = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
assert(rendered:find("1: [No Name]", 1, true), rendered)

-- Tabpage handles need not match their current tab numbers.
vim.cmd("tabnew")
local remaining = vim.api.nvim_get_current_tabpage()
vim.cmd("tabonly!")
assert(remaining ~= 1)
vim.api.nvim_buf_set_name(0, fixture.root .. "/unsafe\n%#ErrorMsg#.lua")
local format = require("sess.ui.tabline").provider()
assert(format:find("%1T%#TabLineSel# 1: unsafe %%#ErrorMsg#.lua ", 1, true), format)
assert(not format:find("%" .. remaining .. "T", 1, true), format)
rendered = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
assert(rendered:find("1: unsafe %#ErrorMsg#.lua", 1, true), rendered)
