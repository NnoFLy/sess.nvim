fixture.setup()
local api = require("sess.api")
local notifications = {}
vim.notify = function(message, level)
    notifications[#notifications + 1] = { message, level }
end
local id = "full:execution:identity"
local snapshot = {
    sessions = {},
    agents_by_id = {},
    marks_by_id = {},
    terminals = {
        {
            id = id,
            owner_id = "inactive",
            owner_name = "Other project",
            name = "server",
            execution_state = "completed",
            available = true,
        },
    },
}
api.active.initial_snapshot = function()
    return snapshot
end
api.active.snapshot_async = function(callback)
    callback(snapshot)
end
api.state.active = function()
    return snapshot.sessions
end
api.state.current = function()
    return nil
end
local sidebar = require("sess.ui.sidebar")
sidebar.configure({ refresh_interval = 60000, active_expand = "none" })
assert(sidebar.open())
local win = vim.api.nvim_get_current_win()
local function key(lhs)
    vim.api.nvim_set_current_win(win)
    return vim.fn.maparg(lhs, "n", false, true).callback()
end
local function select(text)
    local buf = vim.api.nvim_win_get_buf(win)
    for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if line:find(text, 1, true) then
            vim.api.nvim_win_set_cursor(win, { index, 0 })
            vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
            return
        end
    end
    error("missing sidebar row: " .. text)
end
local focuses = 0
api.terminal.focus = function(value)
    assert(value == id)
    focuses = focuses + 1
    key("<CR>") -- reentrant acceptance cannot focus twice
    return true, nil, {}, { "focus diagnostic" }
end
api.session.load = function()
    error("adapter must not load terminal owner")
end
vim.ui.input = function()
    error("terminal/group must not prompt for session mutations")
end
api.session.toggle_pin = function()
    error("terminal/group is not a session")
end
select("Background terminals")
key("<CR>") -- header expands without loading/focusing
key("<CR>") -- accepting an expanded header is a no-op
assert(focuses == 0)
select("server")
key("rr")
key("p")
key("<CR>")
assert(focuses == 1)
-- Collapse falls back to the selected terminal's parent and persists refresh.
select("server")
key("<Tab>")
key("<C-r>")
local lines =
    table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
assert(not lines:find("server", 1, true))
select("Background terminals")
key("<CR>")
select("server")
-- The same identity moving under an active owner stays selected.
snapshot.sessions = { { id = "inactive", metadata = { name = "Other project", cwd = "/other" } } }
key("<C-r>")
local current_line = vim.api.nvim_win_get_cursor(win)[1]
assert(
    vim.api
        .nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), current_line - 1, current_line, false)[1]
        :find("Other", 1, true),
    "moving into a collapsed owner selects that parent"
)
key("<S-Tab>") -- expand the newly active owner
select("server")
api.terminal.focus = function()
    error("focus exception")
end
key("<CR>")
api.terminal.focus = function()
    focuses = focuses + 1
    return false, "unload cancelled"
end
key("<CR>")
assert(focuses == 2, "exception must release pending guard")
local warned, errored = false, false
for _, notification in ipairs(notifications) do
    warned = warned
        or (
            notification[1]:find("focus diagnostic", 1, true) ~= nil
            and notification[2] == vim.log.levels.WARN
        )
    errored = errored
        or (
            notification[1]:find("focus exception", 1, true) ~= nil
            and notification[2] == vim.log.levels.ERROR
        )
end
assert(warned and errored)
assert(sidebar.close())
