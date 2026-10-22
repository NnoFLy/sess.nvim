fixture.setup()
local api = require("sess.api")
local one = { id = "one", metadata = { name = "one", cwd = fixture.root .. "/one" } }
local two = { id = "two", metadata = { name = "two", cwd = fixture.root .. "/two" } }
local snapshot = {
    sessions = { one, two },
    current_id = "two",
    agents_by_id = { one = { { id = "agent", name = "agent", status = "idle" } } },
    marks_by_id = { one = "a" },
}
api.state.active = function()
    return snapshot.sessions
end
api.state.current = function()
    return two
end
api.active.initial_snapshot = function()
    return snapshot
end
local refreshes = 0
api.active.snapshot_async = function(callback)
    refreshes = refreshes + 1
    callback(snapshot)
end
local sidebar = require("sess.ui.sidebar")
sidebar.configure({ active_expand = "all", refresh_interval = 60000 })
assert(sidebar.open())
local win = vim.api.nvim_get_current_win()
local buf = vim.api.nvim_win_get_buf(win)
local function key(lhs)
    return vim.fn.maparg(lhs, "n", false, true).callback()
end
local function cursor(line)
    vim.api.nvim_win_set_cursor(win, { line, 0 })
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
end
local calls = {}
for _, name in ipairs({ "rename", "toggle_pin", "delete", "load" }) do
    api.session[name] = function(id, value)
        calls[#calls + 1] = { name, id, value }
        return true, nil, nil, { "successful " .. name .. " diagnostic" }
    end
end
package.loaded["sess.ui.unload"] = function(id)
    calls[#calls + 1] = { "unload", id }
    return true
end
api.session.list_marks = function()
    return true, nil, { { id = "one", mark = "a" } }, {}
end
api.session.clear_mark = function(mark, options)
    fixture.equal("one", options.expected_id)
    calls[#calls + 1] = { "clear", mark }
    return true
end
api.session.set_mark = function(id, mark)
    calls[#calls + 1] = { "mark", id, mark }
    return true, nil, nil, {}
end
api.agent.focused = function(id)
    fixture.equal("one", id)
    return true, nil, { id = "remembered" }, {}
end
api.agent.focus = function(id, agent)
    calls[#calls + 1] = { "focus", id, agent }
    return true
end
local notifications = {}
vim.notify = function(message, level)
    notifications[#notifications + 1] = { message, level }
end
local input, prompts = "new name", {}
vim.ui.input = function(options, callback)
    prompts[#prompts + 1] = options.prompt
    callback(input)
end
vim.fn.confirm = function(message, _, default)
    fixture.equal(2, default)
    assert(message:find("one", 1, true))
    return 1
end
local copied
vim.fn.setreg = function(register, value)
    fixture.equal("+", register)
    copied = value
    return 0
end

-- Every session action on an agent row targets its parent, not the current
-- session by implication. Input and delete confirmations identify that parent.
cursor(4)
vim.api.nvim_feedkeys("rr", "xt", false)
fixture.equal({ "rename", "one", "new name" }, calls[#calls])
assert(prompts[1]:find("one", 1, true))
key("uu")
fixture.equal({ "unload", "one" }, calls[#calls])
key("dd")
fixture.equal({ "delete", "one" }, calls[#calls])
input = "z"
key("<C-b>")
fixture.equal({ "mark", "one", "z" }, calls[#calls])
key("um")
fixture.equal({ "clear", "a" }, calls[#calls])
key("p")
fixture.equal({ "toggle_pin", "one" }, calls[#calls])
key("<C-y>")
fixture.equal(one.metadata.cwd, copied)
api.state.current = function()
    return one
end
local before_focus = #calls
key("<C-o>")
fixture.equal(before_focus + 1, #calls) -- focus only, never load first
fixture.equal({ "focus", "one", "agent" }, calls[#calls])
key("<CR>")
fixture.equal({ "load", "one" }, calls[#calls - 1])
fixture.equal({ "focus", "one", "agent" }, calls[#calls])
cursor(3)
key("<CR>")
fixture.equal({ "focus", "one", "remembered" }, calls[#calls])
local warned = false
for _, notice in ipairs(notifications) do
    if notice[1]:find("successful rename diagnostic", 1, true) then
        warned = notice[2] == vim.log.levels.WARN
    end
end
assert(warned, "successful diagnostics must not be errors")

-- Header/current-session constraints for focus-only, and clipboard failures.
local count = #calls
key("<C-o>")
fixture.equal(count, #calls)
cursor(4)
api.state.current = function()
    return two
end
key("<C-o>")
fixture.equal(count, #calls)
vim.fn.setreg = function()
    error("clipboard unavailable")
end
key("<C-y>")
assert(notifications[#notifications][1]:find("clipboard unavailable", 1, true))
fixture.equal(vim.log.levels.ERROR, notifications[#notifications][2])
api.session.toggle_pin = function()
    return false, "pin failed"
end
key("p")
assert(notifications[#notifications][1]:find("pin failed", 1, true))
assert(sidebar.is_open())

-- Free cursor locations and placeholders never reuse a remembered target.
local targeted = { "rr", "uu", "dd", "<C-b>", "um", "p", "<C-y>", "<C-o>", "<CR>", "<Tab>" }
local lines = vim.api.nvim_buf_line_count(buf)
count = #calls
local prompt_count = #prompts
for _, line in ipairs({ 1, 2, 6, lines - 2, lines - 1, lines }) do
    cursor(line)
    for _, lhs in ipairs(targeted) do
        key(lhs)
    end
    fixture.equal(line, vim.api.nvim_win_get_cursor(win)[1])
end
fixture.equal(count, #calls)
fixture.equal(prompt_count, #prompts)

-- Tab on an agent toggles the parent; mixed expansion collapses all.
cursor(4)
key("<Tab>")
fixture.equal(8, vim.api.nvim_buf_line_count(buf))
key("<S-Tab>")
fixture.equal(7, vim.api.nvim_buf_line_count(buf)) -- both collapsed
key("<S-Tab>")
fixture.equal(9, vim.api.nvim_buf_line_count(buf)) -- both expanded
local before = refreshes
cursor(1)
key("r")
key("<C-r>")
fixture.equal(before + 2, refreshes)
assert(vim.fn.maparg("r", "n", false, true).nowait == 0, "r must not shadow rr")
assert(sidebar.close())
