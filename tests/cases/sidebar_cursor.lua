fixture.setup()

local api = require("sess.api")
local snapshot = {
    sessions = {
        { id = "one", metadata = { name = "one", cwd = fixture.root .. "/one" } },
        { id = "two", metadata = { name = "two", cwd = fixture.root .. "/two" } },
    },
    agents_by_id = {},
}
local refreshes = 0
api.active.initial_snapshot = function()
    return snapshot
end
api.active.snapshot_async = function(callback)
    refreshes = refreshes + 1
    callback(snapshot)
    return function() end
end

local sidebar = require("sess.ui.sidebar")
sidebar.configure({ refresh_interval = 50 })
assert(sidebar.open())
local win = vim.api.nvim_get_current_win()
local buf = vim.api.nvim_win_get_buf(win)
local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
fixture.equal({ 3, 0 }, vim.api.nvim_win_get_cursor(win))

-- Refresh must not pull the cursor back into the session rows when the user
-- moves onto the title, separators, or footer.
for _, position in ipairs({ { 1, 4 }, { 2, 3 }, { #lines - 2, 3 }, { #lines - 1, 4 }, { #lines, 4 } }) do
    vim.api.nvim_win_set_cursor(win, position)
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
    assert(sidebar.refresh())
    fixture.equal(position, vim.api.nvim_win_get_cursor(win))
    local previous_refreshes = refreshes
    assert(vim.wait(1000, function()
        return refreshes > previous_refreshes
    end, 10), "sidebar should continue polling")
    fixture.equal(position, vim.api.nvim_win_get_cursor(win))
end

-- Explicit session navigation must still move from the footer into the list.
vim.fn.maparg("<C-j>", "n", false, true).callback()
fixture.equal({ 4, 0 }, vim.api.nvim_win_get_cursor(win))
vim.fn.maparg("<C-k>", "n", false, true).callback()
fixture.equal({ 3, 0 }, vim.api.nvim_win_get_cursor(win))
assert(sidebar.close())
