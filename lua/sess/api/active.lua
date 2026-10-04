local agents = require("sess.api.agent")
local sessions = require("sess.api.session")
local state = require("sess.api.state")

local M = {}

local function new_snapshot()
    local active = state.active()
    local current = state.current()
    return {
        sessions = active,
        agents_by_id = {},
        focused_by_id = {},
        marks_by_id = {},
        marks_loaded = false,
        agents_loaded_by_id = {},
        stale_by_id = {},
        current_id = current and current.id or nil,
        diagnostics = {},
    }
end

-- Build the inexpensive part used to open the picker immediately. Agent and
-- mark discovery is deliberately deferred to snapshot_async().
function M.initial_snapshot()
    return new_snapshot()
end

local function add_marks(result)
    local ok, err, entries, diagnostics = sessions.list_marks()
    if not ok then result.diagnostics[#result.diagnostics + 1] = err end
    for _, diagnostic in ipairs(diagnostics or {}) do result.diagnostics[#result.diagnostics + 1] = diagnostic end
    for _, entry in ipairs(entries or {}) do
        if not entry.stale then
            result.marks_by_id[entry.id] = result.marks_by_id[entry.id]
                and (result.marks_by_id[entry.id] .. " @" .. entry.mark)
                or ("@" .. entry.mark)
        end
    end
    result.marks_loaded = true
end

local function add_agents(result, session, previous)
    local called, listed, list_err, found, focused_id, diagnostics = pcall(
        agents.snapshot_active,
        session.id
    )
    local stale = false
    if not called then
        result.diagnostics[#result.diagnostics + 1] = string.format(
            "agent status probe failed for %s: %s",
            session.id,
            tostring(listed)
        )
        stale = true
    elseif not listed then
        result.diagnostics[#result.diagnostics + 1] = list_err
        stale = true
    end
    for _, diagnostic in ipairs(diagnostics or {}) do
        result.diagnostics[#result.diagnostics + 1] = diagnostic
        stale = true
    end
    result.stale_by_id[session.id] = stale or nil
    if stale and previous then
        result.agents_by_id[session.id] = vim.deepcopy(
            (previous.agents_by_id or {})[session.id] or {}
        )
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
    if options.marks ~= false then
        add_marks(result)
    end
    for _, session in ipairs(result.sessions) do
        add_agents(result, session)
    end
    return result
end

-- Build one agent group per event-loop turn. Mark discovery can be skipped for
-- status-only refreshes; callers retain the last completed mark map.
function M.snapshot_async(callback, options)
    options = options or {}
    local include_marks = options.marks ~= false
    local result = new_snapshot()
    local cancelled = false
    local async = vim.async
    if async then
        local task = async.run(function()
            if include_marks then
                add_marks(result)
                async.sleep(0)
            end
            for _, session in ipairs(result.sessions) do
                if cancelled or async.is_closing() then
                    return
                end
                add_agents(result, session, options.previous_snapshot)
                async.sleep(0)
            end
            if not cancelled and not async.is_closing() then
                callback(result)
            end
        end)
        return function()
            cancelled = true
            task:close()
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
            callback(result)
            return
        end

        add_agents(result, session, options.previous_snapshot)
        vim.schedule(step)
    end

    if include_marks then
        vim.schedule(function()
            if cancelled then
                return
            end
            add_marks(result)
            vim.schedule(step)
        end)
    else
        vim.schedule(step)
    end

    return function()
        cancelled = true
    end
end

return M
