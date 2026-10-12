fixture.setup()

local api = require("sess.api")
local _, _, session = api.session.create(fixture.directory("project"))
assert(api.session.load(session.id))

local terminal = vim.api.nvim_create_buf(false, true)
vim.api.nvim_open_term(terminal, {})
vim.b[terminal].terminal_job_id = 99
vim.api.nvim_win_set_buf(0, terminal)

local original_job_info = vim.fn.job_info
local job_info_call_count = 0
vim.fn.job_info = function()
    job_info_call_count = job_info_call_count + 1
    return { status = "run", cmd = { "codex" } }
end

package.loaded["telescope.finders"] = {
    new_table = function(value)
        return value
    end,
}

local finders = require("telescope._extensions.sess.finders")
local finder = finders.generate_active_finder({
    [session.id] = true,
})
assert(#finder.results == 2, vim.inspect(finder.results))
assert(finder.results[2].kind == "agent")
assert(finder.results[2].agent.name == "codex")
assert(finder.results[2].agent.target.bufnr == terminal)

local async_done = false
local cancel_async = finders.generate_active_finder_async(
    {
        [session.id] = true,
    },
    "all",
    function(async_finder, async_rows)
        assert(#async_finder.results == #async_rows)
        async_done = true
    end
)
assert(cancel_async)
assert(
    vim.wait(1000, function()
        return async_done
    end, 10),
    "async active finder did not finish"
)
cancel_async()

-- Active refreshes must not rescan the entire persistent catalog for each
-- already-known active session.
local catalog = require("sess.session")
local original_list = catalog.list
local catalog_lists = 0
catalog.list = function(...)
    catalog_lists = catalog_lists + 1
    return original_list(...)
end
assert(api.active.snapshot())
assert(catalog_lists == 0, "active snapshot rescanned the session catalog")
local calls_after_first_snapshot = job_info_call_count
assert(api.active.snapshot())
assert(
    job_info_call_count == calls_after_first_snapshot,
    "active snapshots should reuse terminal identity within the cache window"
)
catalog.list = original_list

local ok, err, registered = api.agent.register(nil, {
    id = "pi",
    name = "pi",
    bufnr = terminal,
    winid = vim.api.nvim_get_current_win(),
})
assert(ok, err)
assert(registered.target.bufnr == terminal)

local list_ok, list_err, listed = api.agent.list()
assert(list_ok, list_err)
assert(#listed == 1)
assert(listed[1].name == "pi")

-- Active snapshots cache liveness briefly, but must notice an exited job
-- instead of keeping its explicit integration status forever.
api.active.snapshot({ marks = false })
vim.fn.job_info = function()
    return { status = "dead", cmd = { name } }
end
assert(vim.wait(1500, function()
    local snapshot = api.active.snapshot({ marks = false })
    local rows = snapshot.agents_by_id[session.id] or {}
    return rows[1] and rows[1].status == "unknown"
end, 10), "active snapshot did not observe the exited terminal job")
vim.fn.job_info = function()
    return { status = "run", cmd = { name } }
end

-- A failed subsequent probe keeps the last usable agent row while reporting
-- stale data and a diagnostic.
local previous_snapshot = api.active.snapshot({ marks = false })
assert(#previous_snapshot.agents_by_id[session.id] == 1)
assert(previous_snapshot.agents_by_id[session.id][1].name == "pi")
local original_snapshot_active = api.agent.snapshot_active
api.agent.snapshot_active = function()
    error("detector unavailable")
end
local failed_snapshot
api.active.snapshot_async(function(snapshot)
    failed_snapshot = snapshot
end, {
    marks = false,
    previous_snapshot = previous_snapshot,
})
assert(vim.wait(1000, function() return failed_snapshot ~= nil end, 10))
assert(failed_snapshot.stale_by_id[session.id])
assert(failed_snapshot.agents_loaded_by_id[session.id])
assert(failed_snapshot.diagnostics[1]:find("detector unavailable", 1, true))
assert(#failed_snapshot.agents_by_id[session.id] == 1)
assert(failed_snapshot.agents_by_id[session.id][1].name == "pi")
api.agent.snapshot_active = original_snapshot_active

-- A normal unknown observation replaces the old row even when it carries a
-- diagnostic; only an explicitly failed status probe is stale.
local original_snapshot_active_unknown = api.agent.snapshot_active
api.agent.snapshot_active = function()
    return true, nil, {
        {
            id = "pi",
            name = "pi",
            status = "unknown",
            probe_failed = false,
            target = { bufnr = terminal },
            diagnostics = { "unrecognized current screen" },
        },
    }, nil, { "unrecognized current screen" }
end
local unknown_snapshot
api.active.snapshot_async(function(snapshot)
    unknown_snapshot = snapshot
end, { marks = false, previous_snapshot = previous_snapshot })
assert(vim.wait(1000, function() return unknown_snapshot ~= nil end, 10))
assert(not unknown_snapshot.stale_by_id[session.id])
assert(unknown_snapshot.agents_by_id[session.id][1].status == "unknown")
api.agent.snapshot_active = original_snapshot_active_unknown

-- An applicable-only screen probe reports the current unknown row without
-- replacing it with a prior row or marking the session refresh stale.
local nonterminal = vim.api.nvim_create_buf(false, true)
local nonterminal_ok, nonterminal_err = api.agent.register(nil, {
    id = "zz-editor",
    name = "editor",
    bufnr = nonterminal,
})
assert(nonterminal_ok, nonterminal_err)
local nonterminal_previous = api.active.snapshot({ marks = false })
local nonterminal_previous_row
for _, row in ipairs(nonterminal_previous.agents_by_id[session.id]) do
    if row.id == "zz-editor" then
        row.status = "working"
        nonterminal_previous_row = row
        break
    end
end
assert(nonterminal_previous_row, "nonterminal registered row was not discovered")
local nonterminal_snapshot
api.active.snapshot_async(function(snapshot)
    nonterminal_snapshot = snapshot
end, {
    marks = false,
    previous_snapshot = nonterminal_previous,
})
assert(vim.wait(1000, function() return nonterminal_snapshot ~= nil end, 10))
assert(not nonterminal_snapshot.stale_by_id[session.id])
local nonterminal_row
for _, row in ipairs(nonterminal_snapshot.agents_by_id[session.id]) do
    if row.id == "zz-editor" then nonterminal_row = row break end
end
assert(nonterminal_row and nonterminal_row.status == "unknown", vim.inspect(nonterminal_snapshot))
assert(
    nonterminal_row.diagnostics
        and nonterminal_row.diagnostics[1]:find("requires a terminal target", 1, true),
    vim.inspect(nonterminal_row)
)

-- A deleted registered target is a current unknown row, not a transient probe
-- failure. Do not replace it with the prior usable row in the active view.
vim.api.nvim_buf_delete(terminal, { force = true })
local deleted_snapshot = api.active.snapshot({ marks = false })
assert(not deleted_snapshot.stale_by_id[session.id])
assert(deleted_snapshot.agents_by_id[session.id][1].status == "unknown")
assert(#deleted_snapshot.diagnostics > 0)

-- A lifecycle mutation during hydration invalidates the captured active rows;
-- the completion must restart from current runtime membership.
local runtime_state = require("sess.state")
local original_snapshot_active_for_stale = api.agent.snapshot_active
local removed_during_probe = false
api.agent.snapshot_active = function(session_id)
    if not removed_during_probe then
        removed_during_probe = true
        runtime_state.remove_active_session(session.id)
        runtime_state.set_current_session(nil)
    end
    return original_snapshot_active_for_stale(session_id)
end
local refreshed_snapshot
api.active.snapshot_async(function(snapshot)
    refreshed_snapshot = snapshot
end, { marks = false })
assert(vim.wait(1000, function() return refreshed_snapshot ~= nil end, 10))
assert(#refreshed_snapshot.sessions == 0)
api.agent.snapshot_active = original_snapshot_active_for_stale

vim.fn.job_info = original_job_info
