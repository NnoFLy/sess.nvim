vim.o.columns = 110
vim.o.showtabline = 2
local original =
    "%1T%#ErrorMsg#%(left%)%T%=middle%<%2T%#TabLineSel#right%T%7@SessNativeClick@callback%T"
vim.o.tabline = original
assert(require("sess").setup({
    store_path = fixture.root .. "/store",
    smart_auto_load = "none",
    auto_save = false,
    tabline = { enabled = true },
}))
fixture.equal({ enabled = true }, require("sess.api.opts").get().tabline)
local sidebar = require("sess.ui.sidebar")
local tabline = require("sess.ui.tabline")
local installed = vim.o.tabline
local function evaluate()
    return vim.api.nvim_eval_statusline(vim.o.tabline, {
        use_tabline = true,
        maxwidth = vim.o.columns,
        highlights = true,
    })
end
local function heading(expected)
    assert(vim.wait(200, function()
        local win = sidebar.tabline_geometry().win
        return (
            vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1]
            == "ACTIVE SESSIONS"
        ) == expected
    end))
end
fixture.equal(original, vim.fn.eval(installed:sub(3))) -- Closed sidebar preserves FORMAT.
assert(sidebar.open())
local format = vim.fn.eval(installed:sub(3))
assert(format:find(original, 1, true)) -- Native directives are never flattened.
assert(format:find("%7@SessNativeClick@", 1, true))
local rendered = evaluate()
assert(rendered.str:find("ACTIVE SESSIONS", 1, true), rendered.str)
assert(rendered.str:find("left", 1, true), rendered.str)
assert(rendered.str:find("right", 1, true), rendered.str)
assert(vim.tbl_contains(rendered.highlights, function(hl)
    return hl.group == "ErrorMsg"
end, { predicate = true }))
heading(false)
-- %= must expand within the available native region, not leave trailing fill.
vim.o.tabline = "left%=RIGHT"
assert(tabline.install())
rendered = evaluate()
local function right_edge(result)
    return vim.fn.strdisplaywidth(assert(result.str:match("^(.-)RIGHT"))) + #"RIGHT"
end
fixture.equal(vim.o.columns, right_edge(rendered))
for _, visibility in ipairs({ 0, 1, 2 }) do
    vim.o.showtabline = visibility
    vim.api.nvim_exec_autocmds("OptionSet", { pattern = "showtabline" })
    evaluate()
    heading(visibility ~= 2)
    fixture.equal(visibility, vim.o.showtabline)
end
assert(sidebar.close())
sidebar.configure({ position = "right" })
assert(sidebar.open())
rendered = evaluate()
local col = sidebar.tabline_geometry().col
fixture.equal(col, vim.fn.strdisplaywidth(rendered.str:match("^(.-)ACTIVE SESSIONS")))
fixture.equal(vim.o.columns, rendered.width)
fixture.equal(col, right_edge(rendered))
heading(false)
assert(sidebar.close())
fixture.equal(vim.o.columns, right_edge(evaluate()))
assert(sidebar.open())
evaluate()
heading(false)
-- A later provider owns the option outright; neither OptionSet nor redraw adopts it.
vim.o.tabline = "%#WarningMsg#replacement"
vim.api.nvim_exec_autocmds("OptionSet", { pattern = "tabline" })
heading(true)
fixture.equal("replacement", evaluate().str)
fixture.equal("%#WarningMsg#replacement", vim.o.tabline)
assert(sidebar.close())
