fixture.setup()

local api = require("sess.api")
local calls = 0
api.terminal.list = function()
    calls = calls + 1
    return true,
        nil,
        {
            {
                id = "background:full:id",
                owner_id = "inactive",
                owner_name = "Other project",
                name = "server",
                execution_state = "running",
                available = true,
            },
        },
        { "inventory diagnostic" }
end

-- Inventory is independent of active sessions and survives initial-cache reuse.
local completed
api.active.snapshot_async(function(snapshot)
    completed = snapshot
end)
assert(vim.wait(1000, function()
    return completed ~= nil
end, 10))
assert(calls == 1)
assert(completed.terminals_loaded and not completed.terminals_stale)
assert(completed.terminals[1].id == "background:full:id")
assert(vim.tbl_contains(completed.diagnostics, "inventory diagnostic"))
local initial = api.active.initial_snapshot()
assert(initial.terminals_stale and initial.terminals_loaded)
initial.terminals[1].name = "changed"
assert(api.active.initial_snapshot().terminals[1].name == "server")

api.terminal.list = function()
    return false, "inventory unavailable", nil, { "backend diagnostic" }
end
local failed = api.active.snapshot({ previous_snapshot = completed })
assert(failed.terminals_loaded and failed.terminals_stale)
assert(failed.terminals[1].id == "background:full:id")
assert(failed.terminals[1].execution_state == "unknown" and not failed.terminals[1].available)
assert(vim.tbl_contains(failed.diagnostics, "inventory unavailable"))
assert(vim.tbl_contains(failed.diagnostics, "backend diagnostic"))
assert(failed.signature ~= completed.signature)

-- Cancellation must neither publish nor seed the next initial view.
api.terminal.list = function()
    error("cancelled query must not run")
end
local cancel = api.active.snapshot_async(function()
    error("cancelled snapshot published")
end)
cancel()
vim.wait(30, function()
    return false
end, 5)
assert(api.active.initial_snapshot().terminals[1].id == "background:full:id")

local rows = require("sess.ui.rows")
local background_key = rows.key("background_terminals", "")
local view = {
    sessions = { { id = "active", metadata = { name = "Project", cwd = "/project" } } },
    agents_by_id = {
        active = { { id = "explicit", name = "registered agent", status = "working" } },
    },
    terminals = {
        {
            id = "owned",
            owner_id = "active",
            name = "shell",
            execution_state = "running",
            available = true,
        },
        {
            id = "background:full:id",
            owner_id = "inactive",
            owner_name = "Other project",
            name = "server",
            execution_state = "completed",
            available = true,
        },
        { id = "unassigned", name = "shell", execution_state = "unknown", available = false },
        {
            id = "owned",
            owner_id = "active",
            name = "duplicate view",
            execution_state = "running",
            available = true,
        },
    },
}
local built = rows.build_active(
    view,
    { expanded = { active = true, [background_key] = true }, sort = "name" }
)
assert(#built == 6)
assert(built[2].kind == "agent" and built[2].display:find("working", 1, true))
assert(built[3].kind == "terminal" and built[3].id == "owned")
assert(built[3].display:find("running", 1, true) and not built[3].display:find("working", 1, true))
assert(built[4].kind == "background_terminals" and built[4].key == background_key)
assert(built[5].parent_key == background_key and built[5].display:find("Other project", 1, true))
assert(built[5].ordinal:find("background:full:id", 1, true))
assert(built[6].display:find("unknown", 1, true) and built[6].display:find("unavailable", 1, true))
local terminal_key = built[5].key
view.sessions[#view.sessions + 1] = { id = "inactive", metadata = { name = "Other project" } }
built = rows.build_active(view, { expanded = { inactive = true, [background_key] = true } })
local moved
for _, row in ipairs(built) do
    if row.id == "background:full:id" then
        moved = row
    end
end
assert(moved.key == terminal_key and moved.parent_key == rows.session_key("inactive"))

-- Every actionable/display inventory field and diagnostics changes the shared signature.
local entry = { id = "identity", name = "name", execution_state = "running", available = true }
local diagnostic = "first diagnostic"
api.terminal.list = function()
    return true, nil, { vim.deepcopy(entry) }, { diagnostic }
end
local signature = api.active.snapshot().signature
for _, change in ipairs({
    { "owner_id", "owner" },
    { "owner_name", "Owner name" },
    { "name", "new name" },
    { "execution_state", "completed" },
    { "available", false },
    { "id", "other:identity" },
}) do
    entry[change[1]] = change[2]
    local changed = api.active.snapshot()
    assert(changed.signature ~= signature, "signature must include " .. change[1])
    signature = changed.signature
end
diagnostic = "second diagnostic"
assert(api.active.snapshot().signature ~= signature)

-- A failed refresh merges retained backend identities with previous entries;
-- a successful empty inventory, in contrast, confirms removal.
api.terminal.list = function()
    return false, "failed", { { id = "retained" } }, {}
end
local retained = api.active.snapshot({ previous_snapshot = completed })
assert(#retained.terminals == 2 and retained.terminals_stale)
api.terminal.list = function()
    return true, nil, {}, {}
end
assert(#api.active.snapshot({ previous_snapshot = retained }).terminals == 0)

-- Active generation changes discard the candidate and reconcile terminal
-- membership again, rather than publishing a half-old tree.
local arriving
local probes, publications = 0, 0
api.terminal.list = function()
    probes = probes + 1
    if probes == 1 then
        local ok, err
        ok, err, arriving = api.session.create(fixture.directory("arriving"))
        assert(ok, err)
    end
    return true,
        nil,
        {
            {
                id = "after-generation",
                owner_id = arriving.id,
                name = "shell",
                execution_state = "running",
                available = true,
            },
        },
        {}
end
api.active.snapshot_async(function(snapshot)
    publications = publications + 1
    assert(snapshot.sessions[1].id == arriving.id)
    assert(snapshot.terminals[1].owner_id == arriving.id)
end)
assert(vim.wait(1000, function()
    return publications > 0
end, 10))
assert(publications == 1 and probes == 2, vim.inspect({ publications, probes }))

-- A partial inventory failure does not erase successful backend observations.
api.terminal.list = function()
    return false,
        "one association unavailable",
        {
            { id = "verified", name = "shell", execution_state = "running", available = true },
        },
        {}
end
local partial = api.active.snapshot({ previous_snapshot = completed })
assert(partial.terminals[1].execution_state == "running" and partial.terminals[1].available)
assert(partial.terminals[2].execution_state == "unknown" and not partial.terminals[2].available)

-- Length-prefixed values also need collection boundaries: diagnostic text may
-- look exactly like a terminal's six values, but must not mask its removal.
api.terminal.list = function()
    return true,
        nil,
        { { id = "identity", name = "shell", execution_state = "running", available = true } },
        {}
end
local with_terminal = api.active.snapshot()
api.terminal.list = function()
    return true, nil, {}, { "identity", "", "", "shell", "running", "true" }
end
assert(api.active.snapshot().signature ~= with_terminal.signature)
