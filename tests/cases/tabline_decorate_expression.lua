vim.o.showtabline = 2
vim.o.columns = 110
local calls = 0
local current_win = vim.api.nvim_get_current_win()
local editing_win = current_win
local item_calls = 0
_G.SessNativeItem = function()
    item_calls = item_calls + 1
    fixture.equal(current_win, vim.api.nvim_get_current_win())
    fixture.equal(tostring(current_win), vim.g.actual_curwin)
    return vim.g.sess_native_suffix
end
_G.SessNativeProvider = function()
    calls = calls + 1
    fixture.equal(current_win, vim.g.statusline_winid)
    fixture.equal(current_win, vim.api.nvim_get_current_win())
    return "%1T%#ErrorMsg#" .. calls .. "%T%=RIGHT%{v:lua.SessNativeItem()}"
end
vim.g.sess_native_suffix = "A"
local original = "%!v:lua.SessNativeProvider()"
vim.o.tabline = original
assert(require("sess").setup({
    store_path = fixture.root .. "/store",
    smart_auto_load = "none",
    auto_save = false,
}))
local sidebar = require("sess.ui.sidebar")
local tabline = require("sess.ui.tabline")
local function evaluate()
    current_win = vim.api.nvim_get_current_win()
    local before = calls
    local before_items = item_calls
    local result = vim.api.nvim_eval_statusline(vim.o.tabline, {
        use_tabline = true,
        maxwidth = vim.o.columns,
        highlights = true,
    })
    fixture.equal(before + 1, calls)
    fixture.equal(before_items + 1, item_calls)
    return result
end
local first = evaluate()
assert(first.str:find("RIGHTA", 1, true), first.str)
assert(sidebar.open())
vim.api.nvim_set_current_win(editing_win)
local result = evaluate()
assert(result.str:find("ACTIVE SESSIONS", 1, true), result.str)
assert(result.str:find("RIGHTA", 1, true), result.str)
assert(vim.tbl_contains(result.highlights, function(hl)
    return hl.group == "ErrorMsg"
end, { predicate = true }))
vim.g.sess_native_suffix = "B"
assert(evaluate().str:find("RIGHTB", 1, true))
-- The original expression sees the real focused window, even a sidebar window.
current_win = sidebar.tabline_geometry().win
vim.api.nvim_set_current_win(current_win)
evaluate()
assert(sidebar.close())
current_win = vim.api.nvim_get_current_win()
assert(not evaluate().str:find("ACTIVE SESSIONS", 1, true))
-- A provider error must revoke previously confirmed heading ownership.
assert(sidebar.open())
evaluate()
assert(tabline.heading_visible())
-- Per-frame confirmation never changes sidebar text or starts a redraw loop.
vim.wait(30)
local buf = vim.api.nvim_win_get_buf(sidebar.tabline_geometry().win)
local tick = vim.api.nvim_buf_get_changedtick(buf)
for _ = 1, 3 do
    evaluate()
    assert(tabline.heading_visible())
    vim.wait(30)
    fixture.equal(tick, vim.api.nvim_buf_get_changedtick(buf))
end
local settled = calls
vim.wait(60)
fixture.equal(settled, calls)
_G.SessNativeProvider = function()
    error("native provider failure")
end
pcall(vim.cmd.redrawtabline)
assert(not tabline.heading_visible())
vim.wait(30)
local win = sidebar.tabline_geometry().win
fixture.equal(
    "ACTIVE SESSIONS",
    vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1]
)
assert(sidebar.close())
