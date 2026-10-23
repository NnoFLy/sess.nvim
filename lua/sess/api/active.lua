local agents = require("sess.api.agent")
local terminals = require("sess.api.terminal")
local sessions = require("sess.api.session")
local state = require("sess.api.state")

local M = {}

local MAX_DIAGNOSTICS = 64
local MAX_DIAGNOSTIC_LENGTH = 240
local MAX_AGENTS = 256

-- Cache the last completed probe for the next active picker. It is only an
-- initial view; the picker reconciles it immediately.
local cached_snapshot

local function append_diagnostic(result, value)
    if #result.diagnostics >= MAX_DIAGNOSTICS then
        return
    end
    if type(value) ~= "string" then
        value = "active query diagnostic is malformed"
    elseif #value > MAX_DIAGNOSTIC_LENGTH then
        value = value:sub(1, MAX_DIAGNOSTIC_LENGTH)
    end
    result.diagnostics[#result.diagnostics + 1] = value
end

local function new_snapshot()
    local active = state.active()
    local current = state.current()
    local active_by_id = {}
    for _, session in ipairs(active) do
        active_by_id[session.id] = true
    end
    return {
        sessions = active,
        active_by_id = active_by_id,
        terminals = {},
        terminals_loaded = false,
        terminals_stale = false,
        agents_by_id = {},
        focused_by_id = {},
        marks_by_id = {},
        marks_loaded = false,
        agents_loaded_by_id = {},
        stale_by_id = {},
        current_id = current and current.id or nil,
        diagnostics = {},
        generation = state.active_generation(),
    }
end

local function append_signature(parts, value)
    value = tostring(value == nil and "" or value)
    parts[#parts + 1] = tostring(#value) .. ":" .. value
end

-- A compact value signature lets the active picker skip rebuilding Telescope
-- rows when probes return the same data. Keep it deterministic without hashing:
-- status snapshots are small and the string is cheaper than deep equality on
-- every refresh.
local function snapshot_signature(result)
    local parts = {}
    append_signature(parts, result.generation)
    append_signature(parts, result.current_id)
    append_signature(parts, result.marks_loaded == true)
    for _, session in ipairs(result.sessions or {}) do
        append_signature(parts, session.id)
        append_signature(parts, session.metadata and session.metadata.name)
        append_signature(parts, session.metadata and session.metadata.cwd)
        append_signature(parts, session.metadata and session.metadata.last_used_at)
        append_signature(parts, session.metadata and session.metadata.pinned)
        append_signature(parts, result.marks_by_id[session.id])
        append_signature(parts, result.focused_by_id[session.id])
        append_signature(parts, result.stale_by_id[session.id])
        append_signature(parts, result.agents_loaded_by_id[session.id])
        for _, agent in ipairs(result.agents_by_id[session.id] or {}) do
            append_signature(parts, agent.id)
            append_signature(parts, agent.name)
            append_signature(parts, agent.info)
            append_signature(parts, agent.status)
            append_signature(parts, agent.probe_failed)
            append_signature(parts, agent.target and agent.target.bufnr)
            append_signature(parts, agent.target and agent.target.winid)
            for _, diagnostic in ipairs(agent.diagnostics or {}) do
                append_signature(parts, diagnostic)
            end
        end
    end
    append_signature(parts, result.terminals_loaded)
    append_signature(parts, result.terminals_stale)
    append_signature(parts, #(result.terminals or {}))
    for _, terminal in ipairs(result.terminals or {}) do
        for _, field in ipairs({
            "id",
            "owner_id",
            "owner_name",
            "name",
            "execution_state",
            "available",
        }) do
            append_signature(parts, terminal[field])
        end
    end
    append_signature(parts, #(result.diagnostics or {}))
    for _, diagnostic in ipairs(result.diagnostics or {}) do
        append_signature(parts, diagnostic)
    end
    return table.concat(parts, "|")
end

local function complete_snapshot(result)
    result.signature = snapshot_signature(result)
    return result
end

-- Build the inexpensive part used to open the picker immediately. Agent,
-- terminal and mark discovery is deferred to snapshot_async(), unless the previous active
-- picker has a completed probe to reuse.
function M.initial_snapshot()
    local result = new_snapshot()
    if cached_snapshot then
        -- Live state supplies session membership and metadata. Reuse only the
        -- expensive probe results; marks are shown immediately and reloaded lazily.
        result.marks_by_id = vim.deepcopy(cached_snapshot.marks_by_id or {})
        result.marks_loaded = false
        result.terminals = vim.deepcopy(cached_snapshot.terminals or {})
        result.terminals_loaded = cached_snapshot.terminals_loaded == true
        result.terminals_stale = result.terminals_loaded
        result.diagnostics = vim.deepcopy(cached_snapshot.diagnostics or {})
        local loaded_agents = cached_snapshot.agents_loaded_by_id or {}
        for _, session in ipairs(result.sessions) do
            local session_id = session.id
            if loaded_agents[session_id] then
                result.agents_by_id[session_id] =
                    vim.deepcopy(cached_snapshot.agents_by_id[session_id] or {})
                result.focused_by_id[session_id] = cached_snapshot.focused_by_id[session_id]
                result.agents_loaded_by_id[session_id] = true
                -- Cached rows are useful immediately but remain visibly stale
                -- until the live probe commits.
                result.stale_by_id[session_id] = true
            end
        end
    end
    return complete_snapshot(result)
end

-- A failed inventory is not evidence of closure. Keep identities visible, but
-- never present last-known availability or execution state as a live result.
-- Successful per-entry backend observations remain authoritative on partial failure.
local function add_terminals(result, previous)
    local called, ok, err, entries, diagnostics = pcall(terminals.list)
    local failed = not called or not ok
    if not called then
        append_diagnostic(result, "terminal inventory failed: " .. tostring(ok))
    elseif not ok and err then
        append_diagnostic(result, err)
    end
    if type(diagnostics) == "table" then
        for _, diagnostic in ipairs(diagnostics) do
            append_diagnostic(result, diagnostic)
        end
    elseif diagnostics ~= nil then
        append_diagnostic(result, "terminal inventory diagnostics were malformed")
        failed = true
    end
    if entries ~= nil and type(entries) ~= "table" then
        append_diagnostic(result, "terminal inventory result was malformed")
        entries, failed = nil, true
    end
    local inventory, seen = {}, {}
    local function retain(values, unavailable)
        for _, entry in ipairs(values or {}) do
            if type(entry) == "table" and type(entry.id) == "string" and not seen[entry.id] then
                local value = vim.deepcopy(entry)
                if unavailable then
                    value.execution_state, value.available = "unknown", false
                end
                inventory[#inventory + 1], seen[entry.id] = value, true
            end
        end
    end
    retain(entries)
    if failed then
        retain(previous and previous.terminals, true)
    end
    result.terminals = inventory
    result.terminals_loaded = true
    result.terminals_stale = failed
end

local function add_marks(result)
    local ok, err, entries, diagnostics = sessions.list_marks()
    if not ok and err then
        result.diagnostics[#result.diagnostics + 1] = err
    end
    for _, diagnostic in ipairs(diagnostics or {}) do
        result.diagnostics[#result.diagnostics + 1] = diagnostic
    end
    if not ok then
        -- A failed probe is not an empty registry. Keep the previous map so a
        -- transient storage failure cannot erase marks from the display.
        return false
    end
    result.marks_by_id = {}
    for _, entry in ipairs(entries or {}) do
        if not entry.stale then
            local mark = result.marks_by_id[entry.id]
            result.marks_by_id[entry.id] = mark and (mark .. " @" .. entry.mark)
                or ("@" .. entry.mark)
        end
    end
    result.marks_loaded = true
    return true
end

local function add_agents(result, session, previous)
    local called, listed, list_err, found, focused_id, diagnostics =
        pcall(agents.snapshot_active, session.id)
    local stale = false
    if not called then
        append_diagnostic(
            result,
            string.format("agent status probe failed for %s: %s", session.id, tostring(listed))
        )
        stale = true
    elseif not listed then
        append_diagnostic(result, list_err)
        stale = true
    end
    if found ~= nil and type(found) ~= "table" then
        append_diagnostic(result, "agent status result contained malformed agents")
        stale = true
        found = {}
    elseif type(found) == "table" and #found > MAX_AGENTS then
        append_diagnostic(result, "agent status result contained too many agents")
        stale = true
        found = {}
    end
    local probe_failed = false
    for _, agent in ipairs(found or {}) do
        if type(agent) == "table" and agent.probe_failed == true then
            probe_failed = true
            break
        end
    end
    if diagnostics ~= nil and type(diagnostics) ~= "table" then
        append_diagnostic(result, "agent status diagnostics were malformed")
        stale = true
    else
        for _, diagnostic in ipairs(diagnostics or {}) do
            append_diagnostic(result, diagnostic)
        end
    end
    stale = stale or probe_failed
    result.stale_by_id[session.id] = stale or nil
    if stale and previous then
        result.agents_by_id[session.id] =
            vim.deepcopy((previous.agents_by_id or {})[session.id] or {})
        result.focused_by_id[session.id] = (previous.focused_by_id or {})[session.id]
    else
        result.agents_by_id[session.id] = found or {}
        result.focused_by_id[session.id] = focused_id
    end
    result.agents_loaded_by_id[session.id] = true
end

-- Compose the active-session view once at the application boundary. UI
-- adapters receive a stable, read-only snapshot instead of making N+1 calls.
function M.snapshot(options)
    options = options or {}
    local result = new_snapshot()
    local previous = options.previous_snapshot or cached_snapshot
    if previous then
        result.marks_by_id = vim.deepcopy(previous.marks_by_id or {})
        result.marks_loaded = previous.marks_loaded == true
    end
    if options.marks ~= false then
        add_marks(result)
    end
    for _, session in ipairs(result.sessions) do
        add_agents(result, session, previous)
    end
    add_terminals(result, previous)
    local completed = complete_snapshot(result)
    cached_snapshot = cached_snapshot or {}
    for _, field in ipairs({ "terminals", "terminals_loaded", "terminals_stale", "diagnostics" }) do
        cached_snapshot[field] = vim.deepcopy(completed[field])
    end
    if options.marks ~= false then
        cached_snapshot.marks_by_id = vim.deepcopy(completed.marks_by_id)
        cached_snapshot.marks_loaded = completed.marks_loaded
    end
    return completed
end

-- Build one agent group per event-loop turn. Mark discovery can be skipped for
-- status-only refreshes; callers retain the last completed mark map.
function M.snapshot_async(callback, options)
    options = options or {}
    local include_marks = options.marks ~= false
    local previous = options.previous_snapshot or cached_snapshot
    local result = new_snapshot()
    if options.previous_snapshot then
        result.marks_by_id = vim.deepcopy(options.previous_snapshot.marks_by_id or {})
        result.marks_loaded = options.previous_snapshot.marks_loaded == true
    end
    local cancelled = false
    local restart_cancel

    local function report_error(err)
        if cancelled or type(options.on_error) ~= "function" then
            return
        end
        pcall(options.on_error, err)
    end

    local function complete()
        if cancelled then
            return
        end
        -- A lifecycle mutation can happen while agent probes yield. Never
        -- hand a stale active row set to the picker; restart from live state.
        if state.active_generation() ~= result.generation then
            restart_cancel = M.snapshot_async(callback, options)
            return
        end
        complete_snapshot(result)
        -- Cache only completed snapshots; cancelled or partial results must not
        -- seed the next picker's initial view.
        cached_snapshot = vim.deepcopy(result)
        local ok, err = pcall(callback, result)
        if not ok then
            report_error(err)
        end
    end

    local async = vim.async
    if async then
        local task = async.run(function()
            if include_marks then
                local ok, err = pcall(add_marks, result)
                if not ok then
                    report_error(err)
                    return
                end
                async.sleep(0)
            end
            for _, session in ipairs(result.sessions) do
                if cancelled or async.is_closing() then
                    return
                end
                local ok, err = pcall(add_agents, result, session, previous)
                if not ok then
                    report_error(err)
                    return
                end
                async.sleep(0)
            end
            if not cancelled and not async.is_closing() then
                add_terminals(result, previous)
                complete()
            end
        end)
        return function()
            cancelled = true
            task:close()
            if restart_cancel then
                restart_cancel()
                restart_cancel = nil
            end
        end
    end

    local index = 0
    local function step()
        if cancelled then
            return
        end
        index = index + 1
        local session = result.sessions[index]
        if not session then
            add_terminals(result, previous)
            complete()
            return
        end

        local ok, err = pcall(add_agents, result, session, previous)
        if not ok then
            report_error(err)
            return
        end
        vim.schedule(step)
    end

    if include_marks then
        vim.schedule(function()
            if cancelled then
                return
            end
            local ok, err = pcall(add_marks, result)
            if not ok then
                report_error(err)
                return
            end
            vim.schedule(step)
        end)
    else
        vim.schedule(step)
    end

    return function()
        cancelled = true
        if restart_cancel then
            restart_cancel()
            restart_cancel = nil
        end
    end
end

return M
