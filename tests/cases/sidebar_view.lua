fixture.setup()
local api = require("sess.api")
local sessions = {
    { id = "a", metadata = { name = "Zulu", cwd = "/a", last_used_at = 1 } },
    { id = "b", metadata = { name = "Beta", cwd = "/b", last_used_at = 9, pinned = true } },
    { id = "c", metadata = { name = "Alpha", cwd = "/c", last_used_at = 3 } },
}
local snapshot = {
    sessions = sessions,
    current_id = "a",
    agents_by_id = {},
    marks_by_id = { a = "z" },
}
api.state.active = function()
    return sessions
end
api.state.current = function()
    return sessions[1]
end
api.active.initial_snapshot = function()
    return snapshot
end
api.active.snapshot_async = function(done)
    done(snapshot)
end
local sidebar = require("sess.ui.sidebar")
sidebar.configure({ refresh_interval = 60000 })
assert(sidebar.open())
local win = vim.api.nvim_get_current_win()
local buf = vim.api.nvim_get_current_buf()
local function key(lhs)
    return vim.fn.maparg(lhs, "n", false, true).callback()
end
local function order(expected, mode)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    for index, name in ipairs(expected) do
        assert(lines[index + 2]:find(name, 1, true), vim.inspect(lines))
    end
    assert(lines[#lines]:find("sort: " .. mode, 1, true))
end
order({ "Zulu", "Beta", "Alpha" }, "default")
vim.api.nvim_win_set_cursor(win, { 1, 0 }) -- view-wide sort works off-row
key("<C-s>")
fixture.equal({ 1, 0 }, vim.api.nvim_win_get_cursor(win))
order({ "Beta", "Alpha", "Zulu" }, "recent")
key("<C-s>")
order({ "Beta", "Alpha", "Zulu" }, "pinned")
key("<C-s>")
order({ "Zulu", "Beta", "Alpha" }, "activity")
key("<C-s>")
order({ "Alpha", "Beta", "Zulu" }, "name")
assert(sidebar.refresh())
order({ "Alpha", "Beta", "Zulu" }, "name")
local rows = require("sess.ui.rows")
local original_build = rows.build_active
rows.build_active = function()
    error("sort build failure")
end
key("<C-s>")
rows.build_active = original_build
order({ "Alpha", "Beta", "Zulu" }, "name")
local original_set_lines = vim.api.nvim_buf_set_lines
local failed = false
vim.api.nvim_buf_set_lines = function(target, ...)
    if target == buf and not failed then
        failed = true
        error("sort render failure")
    end
    return original_set_lines(target, ...)
end
key("<C-s>")
vim.api.nvim_buf_set_lines = original_set_lines
assert(failed)
order({ "Alpha", "Beta", "Zulu" }, "name")
key("<C-s>")
order({ "Zulu", "Beta", "Alpha" }, "default")

-- Pin display is opt-in for the sidebar; Telescope's shared default is unchanged.
local default_rows = rows.build_active(snapshot, {})
local pinned_rows = rows.build_active(snapshot, { show_pinned = true, show_metadata = false })
assert(not default_rows[2].display:find("★", 1, true))
assert(pinned_rows[2].display:find("★", 1, true))
assert(pinned_rows[1].display:find("z", 1, true))
local ascii =
    rows.build_active(snapshot, { show_pinned = true, show_metadata = false, icons = false })
assert(ascii[2].display:find("*", 1, true))
for width = 1, 24 do
    local width_rows = rows.build_active(snapshot, { show_pinned = true, available_width = width })
    for _, row in ipairs(width_rows) do
        assert(vim.fn.strdisplaywidth(row.display) <= width)
    end
end

-- A failing native window creation cleans its scratch buffer without moving focus.
local before_buffers = vim.api.nvim_list_bufs()
local original_open_win = vim.api.nvim_open_win
vim.api.nvim_open_win = function()
    error("help open failure")
end
key("?")
vim.api.nvim_open_win = original_open_win
fixture.equal(win, vim.api.nvim_get_current_win())
for _, target in ipairs(vim.api.nvim_list_bufs()) do
    assert(vim.list_contains(before_buffers, target), "failed help left an orphan buffer")
end

-- Scrollable help includes every mapping and selection-specific restrictions,
-- excludes transient resources from captures, and leaves free cursor/view alone.
vim.api.nvim_win_set_cursor(win, { 1, 4 })
local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
key("?")
local help_win, help_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
assert(help_win ~= win)
assert(vim.b[help_buf].sess_transient_ui)
local text = table.concat(vim.api.nvim_buf_get_lines(help_buf, 0, -1, false), "\n")
for _, lhs in ipairs({
    "<CR>",
    "<Tab>",
    "<S-Tab>",
    "<C-j>",
    "<C-k>",
    "<C-r>",
    "rr",
    "uu",
    "dd",
    "<C-b>",
    "um",
    "p",
    "<C-y>",
    "<C-o>",
    "<C-s>",
    "?",
    "q",
    "<Esc>",
    "<LeftMouse>",
    "<2-LeftMouse>",
}) do
    assert(text:find(lhs, 1, true), lhs)
end
assert(text:find("cursor is not on a session/agent row", 1, true))
local capture = require("sess.editor").capture()
assert(not capture.buffers[buf] and not capture.buffers[help_buf])
assert(vim.api.nvim_win_get_height(help_win) < vim.api.nvim_buf_line_count(help_buf))
key("q")
assert(not vim.api.nvim_win_is_valid(help_win))
assert(not vim.api.nvim_buf_is_valid(help_buf))
fixture.equal(win, vim.api.nvim_get_current_win())
fixture.equal(view, vim.api.nvim_win_call(win, vim.fn.winsaveview))
vim.api.nvim_win_set_cursor(win, { 3, 0 })
key("?")
text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
assert(text:find("select an agent row", 1, true))
key("<Esc>")
key("?")
help_win, help_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
vim.api.nvim_win_close(help_win, true)
assert(not vim.api.nvim_buf_is_valid(help_buf))
fixture.equal(win, vim.api.nvim_get_current_win())
key("?")
help_win, help_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
vim.cmd("tabnew")
assert(not vim.api.nvim_win_is_valid(help_win) and not vim.api.nvim_buf_is_valid(help_buf))
assert(sidebar.is_open())
vim.cmd("tabclose")
vim.api.nvim_set_current_win(vim.fn.bufwinid("Sess Sidebar"))
key("?")
help_win, help_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
assert(sidebar.close())
assert(not vim.api.nvim_win_is_valid(help_win) and not vim.api.nvim_buf_is_valid(help_buf))
assert(sidebar.open())
win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
order({ "Zulu", "Beta", "Alpha" }, "default")
key("<C-s>")
assert(sidebar.close())
assert(sidebar.open())
win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
order({ "Zulu", "Beta", "Alpha" }, "default")
assert(sidebar.close())
