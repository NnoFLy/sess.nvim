fixture.setup()

local api = require("sess.api")
local sidebar = require("sess.ui.sidebar")
local one = { id = "one", metadata = { name = "one", cwd = fixture.root .. "/one" } }
local two = { id = "two", metadata = { name = "two", cwd = fixture.root .. "/two" } }
local snapshot
api.active.initial_snapshot = function()
    return snapshot
end
api.active.snapshot_async = function(callback)
    callback(snapshot)
end

local function has_agent(buf, name)
    for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if line:find(name, 1, true) then
            return true
        end
    end
    return false
end

-- New sessions follow the configured default without resetting manual choices.
for _, mode in ipairs({ "all", "none", "current" }) do
    snapshot = {
        sessions = { one },
        current_id = "one",
        agents_by_id = { one = { { id = "a", name = "agent-one", status = "idle" } } },
    }
    local options = { refresh_interval = 60000 }
    if mode ~= "all" then
        options.active_expand = mode
    end
    sidebar.configure(options)
    assert(sidebar.open())
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_win_get_buf(win)
    fixture.equal(mode ~= "none", has_agent(buf, "agent-one"))
    if mode ~= "none" then
        vim.api.nvim_win_set_cursor(win, { 3, 0 })
        vim.fn.maparg("<Tab>", "n", false, true).callback()
        assert(not has_agent(buf, "agent-one"))
    end

    -- The new session can arrive before its agents are hydrated.
    snapshot.sessions = { one, two }
    snapshot.current_id = "two"
    assert(sidebar.refresh())
    snapshot.agents_by_id.two = { { id = "b", name = "agent-two", status = "idle" } }
    assert(sidebar.refresh())
    assert(not has_agent(buf, "agent-one"), "refresh must preserve manual collapse")
    fixture.equal(mode ~= "none", has_agent(buf, "agent-two"))
    assert(sidebar.refresh())
    fixture.equal(mode ~= "none", has_agent(buf, "agent-two"))
    assert(sidebar.close())
end
