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

vim.fn.job_info = original_job_info
