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
local tabline = require("sess.ui.tabline")
local installed = vim.o.tabline
-- Reinstalling the supplied UI must not wrap it a second time.
assert(tabline.install())
fixture.equal(installed, vim.o.tabline)
local sidebar = require("sess.ui.sidebar")
assert(sidebar.open())
local rendered = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
assert(rendered:find("ACTIVE SESSIONS", 1, true), rendered)
assert(rendered:find("1: [No Name]", 1, true), rendered)
assert(tabline.heading_visible())
local win = sidebar.tabline_geometry().win
assert(vim.wait(200, function()
    return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1]
        ~= "ACTIVE SESSIONS"
end))
-- A provider installed later is never adopted.
vim.o.tabline = "%1Tlater%T"
vim.api.nvim_exec_autocmds("OptionSet", { pattern = "tabline" })
vim.cmd.redrawtabline()
vim.wait(20)
fixture.equal("%1Tlater%T", vim.o.tabline)
assert(not tabline.heading_visible())
assert(sidebar.close())
