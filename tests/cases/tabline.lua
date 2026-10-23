vim.o.showtabline = 1
vim.o.tabline = ""
fixture.setup()
assert(vim.o.showtabline == 1)
assert(vim.o.tabline ~= "")
local sidebar = require("sess.ui.sidebar")
local tabline = require("sess.ui.tabline")
local expression = vim.o.tabline
local api = require("sess.api")
local session = { id = "one", metadata = { name = "one", cwd = fixture.root } }
local snapshot = { sessions = { session }, agents_by_id = {}, marks_by_id = {} }
api.active.initial_snapshot = function()
    return snapshot
end
api.active.snapshot_async = function(callback)
    callback(snapshot)
end
api.state.active = function()
    return { session }
end
local pinned
api.session.toggle_pin = function(id)
    pinned = id
    return true
end

local function sidebar_window()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)):match("Sess Sidebar$") then
            return win
        end
    end
    error("sidebar missing")
end

local function heading(expected)
    assert(
        vim.wait(200, function()
            local buf = vim.api.nvim_win_get_buf(sidebar_window())
            local first = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
            return (first == "ACTIVE SESSIONS") == expected
        end),
        "unexpected in-buffer heading visibility"
    )
end

local function select_session()
    local win = sidebar_window()
    local buf = vim.api.nvim_win_get_buf(win)
    for line, value in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if value:find("one", 1, true) then
            vim.api.nvim_win_set_cursor(win, { line, 0 })
            vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
            return line
        end
    end
    error("session row missing")
end

local function evaluate()
    local format = vim.fn.eval(vim.o.tabline:sub(3))
    local value = vim.api.nvim_eval_statusline(format, {
        use_tabline = true,
        maxwidth = vim.o.columns,
        highlights = true,
    })
    return value.str, format, value.highlights
end

local function option(name, value)
    vim.o[name] = value
    -- OptionSet is suppressed during startup (the isolated runner uses -c).
    vim.api.nvim_exec_autocmds("OptionSet", { pattern = name })
end

vim.o.columns = 110
assert(not tabline.setup(nil))
assert(not tabline.setup(""))
-- Invalid low-level registrations preserve the automatically installed one.
local first_tab = vim.api.nvim_get_current_tabpage()
local first_win = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_name(0, fixture.root .. "/first.lua")
assert(sidebar.open())
assert(tabline.label(first_tab) == "first.lua")
select_session()
assert(not evaluate():find("ACTIVE SESSIONS", 1, true))
heading(true) -- showtabline=1 and one tab: no integrated heading.

vim.cmd("tabnew")
local second_tab = vim.api.nvim_get_current_tabpage()
local second_win = vim.api.nvim_get_current_win()
vim.api.nvim_buf_set_name(0, fixture.root .. "/second.lua")
local text, format, highlights = evaluate()
heading(false)
assert(text:sub(1, 16) == "ACTIVE SESSIONS ")
assert(text:find("1: first.lua", 1, true))
assert(text:find("2: second.lua", 1, true))
assert(format:find("%1T", 1, true) and format:find("%2T", 1, true))
assert(format:find("%T%#SessSidebarTitle#", 1, true))
assert(vim.tbl_contains(highlights, function(hl)
    return hl.group == "TabLineSel"
end, { predicate = true }))

-- Heading ownership survives sidebar reattachment before the next tabline
-- evaluation; checking only after evaluate() would miss the flickering frame.
local session_line = select_session()
for _, tab in ipairs({ first_tab, second_tab }) do
    vim.api.nvim_set_current_tabpage(tab)
    assert(tabline.heading_visible(), "tab switch temporarily returned heading to sidebar")
    sidebar.redraw_heading()
    local buf = vim.api.nvim_win_get_buf(sidebar_window())
    assert(vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= "ACTIVE SESSIONS")
    assert(vim.api.nvim_win_get_cursor(sidebar_window())[1] == session_line)
end

-- Remember the genuinely focused editing split, not the first window/buffer.
vim.cmd("vsplit")
local focused = vim.api.nvim_get_current_win()
vim.cmd("enew")
vim.api.nvim_buf_set_name(0, fixture.root .. "/100%#ErrorMsg#界é.lua")
vim.api.nvim_set_current_win(sidebar_window())
assert(tabline.label(second_tab) == "100%%#ErrorMsg#界é.lua")
text, format = evaluate()
assert(text:find("100%#ErrorMsg#界é.lua", 1, true))
assert(format:find("100%%#ErrorMsg#界é.lua", 1, true))
local transient = vim.api.nvim_create_buf(false, true)
vim.b[transient].sess_transient_ui = true
local float = vim.api.nvim_open_win(transient, true, {
    relative = "editor",
    row = 3,
    col = 35,
    width = 10,
    height = 2,
})
assert(tabline.label(second_tab) == "100%%#ErrorMsg#界é.lua")
vim.api.nvim_win_close(float, true)
vim.api.nvim_set_current_win(sidebar_window())
vim.api.nvim_set_current_tabpage(first_tab)
assert(tabline.label(second_tab) == "100%%#ErrorMsg#界é.lua")
vim.api.nvim_set_current_tabpage(second_tab)
vim.api.nvim_set_current_win(sidebar_window())
assert(tabline.label(second_tab) == "100%%#ErrorMsg#界é.lua")

-- Invalid remembered window/buffer must fall back to another editor window.
vim.api.nvim_win_close(focused, true)
assert(tabline.label(second_tab) == "second.lua")
vim.api.nvim_set_current_win(second_win)
local old_buf = vim.api.nvim_get_current_buf()
local eventignore = vim.o.eventignore
vim.o.eventignore = "all" -- Simulate a stale remembered buffer after external cleanup.
vim.cmd("enew")
vim.api.nvim_buf_delete(old_buf, { force = true })
vim.api.nvim_set_current_win(sidebar_window())
vim.o.eventignore = eventignore
assert(not vim.api.nvim_buf_is_valid(old_buf))
assert(tabline.label(second_tab) == "[No Name]")
assert(tabline.label(-123) == "[No Name]")

vim.api.nvim_set_current_tabpage(first_tab)
assert(tabline.label(first_tab) == "first.lua")
assert(tabline.label(second_tab) == "[No Name]")
evaluate()
heading(false)
local win = sidebar_window()
vim.api.nvim_win_set_width(win, 27)
assert(tabline.heading_visible(), "resize temporarily returned heading to sidebar")
sidebar.redraw_heading()
assert(
    vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, 1, false)[1] ~= "ACTIVE SESSIONS"
)
text = evaluate()
heading(false)
assert(text:sub(30, 31) == "1:", text) -- actual width plus separator, then tab's leading space.

-- Hidden/replaced/disabled tablines restore the original heading, keeping
-- selected row, action targets and semantic highlights aligned.
local selected_line = select_session()
option("showtabline", 0)
heading(true)
assert(vim.api.nvim_win_get_cursor(sidebar_window())[1] == selected_line + 1)
option("showtabline", 2)
evaluate()
heading(false)
assert(vim.api.nvim_win_get_cursor(sidebar_window())[1] == selected_line)
vim.api.nvim_set_current_win(sidebar_window())
vim.fn.maparg("p", "n", false, true).callback()
assert(pinned == "one")
evaluate()
heading(false)
local marks = vim.api.nvim_buf_get_extmarks(
    vim.api.nvim_win_get_buf(sidebar_window()),
    vim.api.nvim_get_namespaces()["sess-sidebar"],
    0,
    -1,
    { details = true }
)
assert(vim.tbl_contains(marks, function(mark)
    return mark[2] == selected_line - 1 and mark[4].hl_group == "SessSidebarActive"
end, { predicate = true }))
option("tabline", "%!v:lua.UnrelatedTabLine()")
heading(true)
assert(tabline.render("%1Tunchanged%T") == "%1Tunchanged%T")
option("tabline", expression)
evaluate()
heading(false)
assert(tabline.setup(false))
heading(true)
-- Existing low-level custom registrations still work without owning options.
expression = "%!v:lua.SessTestTabLine()"
option("tabline", expression)
_G.SessTestTabLine = function()
    return "waiting for integration"
end
assert(tabline.setup(expression))
assert(not tabline.heading_visible(), "new registration must wait for its renderer")
_G.SessTestTabLine = tabline.provider
evaluate()
heading(false)
local list_uis = vim.api.nvim_list_uis
vim.api.nvim_list_uis = function()
    return { { ext_tabline = true } }
end
assert(tabline.render("unchanged") == "unchanged")
heading(true)
vim.api.nvim_list_uis = list_uis
evaluate()
heading(false)

assert(sidebar.close())
local closed = tabline.provider()
assert(not closed:find("ACTIVE SESSIONS", 1, true))
assert(closed:find("%1T%#TabLineSel# 1: first.lua ", 1, true))
assert(sidebar.open())
evaluate()
heading(false)

-- Right offset starts exactly at the displayed sidebar column, including
-- when content must be clipped. Keep native click and highlight directives.
assert(sidebar.close())
sidebar.configure({ position = "right" })
vim.api.nvim_set_current_win(first_win)
assert(sidebar.open())
local offset = sidebar.tabline_geometry()
text, format = evaluate()
heading(false)
assert(vim.fn.strdisplaywidth(text:match("^(.-)ACTIVE SESSIONS")) == offset.col)
assert(format:find("%1T", 1, true))
vim.api.nvim_set_current_win(first_win)
vim.api.nvim_buf_set_name(0, fixture.root .. "/" .. string.rep("界%", 60) .. ".lua")
text = evaluate()
assert(vim.fn.strdisplaywidth(text:match("^(.-)ACTIVE SESSIONS")) == offset.col, text)
assert(vim.fn.strdisplaywidth(text) == vim.o.columns)
vim.o.columns = 120
vim.api.nvim_exec_autocmds("VimResized", {})
offset = sidebar.tabline_geometry()
text = evaluate()
heading(false)
assert(vim.fn.strdisplaywidth(text:match("^(.-)ACTIVE SESSIONS")) == offset.col, text)
-- A narrow right sidebar truncates only the heading using display cells.
vim.api.nvim_win_set_width(sidebar_window(), 10)
text = evaluate()
assert(text:find("ACTIVE SE", 1, true))
assert(vim.fn.strdisplaywidth(text) == vim.o.columns)

-- One remaining tab hides showtabline=1 again, including on reopen.
vim.api.nvim_win_set_width(sidebar_window(), 32)
option("showtabline", 1)
vim.cmd("tabonly!")
evaluate()
heading(true)
assert(sidebar.close())
assert(sidebar.open())
evaluate()
heading(true)
option("showtabline", 2)
evaluate()
heading(false)
assert(sidebar.close())
assert(vim.o.showtabline == 2) -- helper never changes this preference.

-- Opening from a non-first editing split must remember it before sidebar focus.
vim.cmd("vsplit")
vim.cmd("enew")
vim.api.nvim_buf_set_name(0, fixture.root .. "/last.lua")
local last_win = vim.api.nvim_get_current_win()
assert(sidebar.open())
assert(tabline.label() == "last.lua")
local first_buf = vim.api.nvim_win_get_buf(first_win)
local last_buf = vim.api.nvim_win_get_buf(last_win)
vim.b[first_buf].sess_transient_ui = true
vim.b[last_buf].sess_transient_ui = true
assert(tabline.label() == "[No Name]")
vim.b[first_buf].sess_transient_ui = nil
vim.b[last_buf].sess_transient_ui = nil
assert(sidebar.close())
assert(tabline.setup(false))
