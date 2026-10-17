fixture.setup()

local api = require("sess.api")
local _, _, session = api.session.create(fixture.directory("cached"))
assert(api.session.load(session))

local agent_api = api.agent
local original_snapshot_active = agent_api.snapshot_active
local status = "working"
agent_api.snapshot_active = function(session_id)
    assert(session_id == session.id)
    return true, nil, {
        { id = "pi", name = "pi", status = status },
    }, "pi", {}
end

local completed
api.active.snapshot_async(function(snapshot)
    completed = snapshot
end)
assert(vim.wait(1000, function() return completed ~= nil end, 10))
assert(completed.agents_by_id[session.id][1].status == "working")

-- The next picker can render the last completed probe before running a new
-- one. Cached rows are explicitly marked stale so the UI does not imply that
-- they are live.
local initial = api.active.initial_snapshot()
assert(initial.agents_by_id[session.id][1].status == "working")
assert(initial.agents_loaded_by_id[session.id])
assert(initial.stale_by_id[session.id])
assert(not initial.marks_loaded)

-- The cache and every initial view are defensive copies.
initial.agents_by_id[session.id][1].status = "corrupted"
local next_initial = api.active.initial_snapshot()
assert(next_initial.agents_by_id[session.id][1].status == "working")

-- A synchronous refresh keeps the last-known mark map when the mark probe
-- fails, while retaining both the primary error and probe diagnostics.
assert(api.session.set_mark(session, "m"))
local marked = api.active.snapshot()
assert(marked.marks_by_id[session.id] == "@m")
local original_list_marks = api.session.list_marks
api.session.list_marks = function()
    return false, "injected mark probe failure", nil, { "injected mark diagnostic" }
end
local failed_marks = api.active.snapshot()
api.session.list_marks = original_list_marks
assert(failed_marks.marks_by_id[session.id] == "@m")
assert(failed_marks.marks_loaded)
assert(vim.tbl_contains(failed_marks.diagnostics, "injected mark probe failure"))
assert(vim.tbl_contains(failed_marks.diagnostics, "injected mark diagnostic"))

-- A lazy refresh replaces the cached rows with the fresh probe result.
status = "idle"
local refreshed
api.active.snapshot_async(function(snapshot)
    refreshed = snapshot
end, { previous_snapshot = next_initial })
assert(vim.wait(1000, function() return refreshed ~= nil end, 10))
assert(refreshed.agents_by_id[session.id][1].status == "idle")
assert(not refreshed.stale_by_id[session.id])

agent_api.snapshot_active = original_snapshot_active
