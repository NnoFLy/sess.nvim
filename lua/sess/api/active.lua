local agents = require("sess.api.agent")
local sessions = require("sess.api.session")
local state = require("sess.api.state")

local M = {}

local function new_snapshot()
    local active = state.active()
    return {
        sessions = active,
        agents_by_id = {},
        focused_by_id = {},
        marks_by_id = {},
        current_id = state.current() and state.current().id or nil,
        diagnostics = {},
    }
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
end

local function add_agents(result, session)
    local listed, list_err, found, focused_id, diagnostics = agents.snapshot(session.id)
    if not listed then result.diagnostics[#result.diagnostics + 1] = list_err end
    for _, diagnostic in ipairs(diagnostics or {}) do result.diagnostics[#result.diagnostics + 1] = diagnostic end
    result.agents_by_id[session.id] = found or {}
    result.focused_by_id[session.id] = focused_id
end

-- Compose the active-session view once at the application boundary. UI
-- adapters receive a stable, read-only snapshot instead of making N+1 calls.
function M.snapshot()
    local result = new_snapshot()
    add_marks(result)
    for _, session in ipairs(result.sessions) do
        add_agents(result, session)
    end
    return result
end

-- Build one agent group per event-loop turn. Neovim API calls must stay on the
-- main thread, but yielding between sessions keeps the picker responsive.
function M.snapshot_async(callback)
    local result = new_snapshot()
    add_marks(result)

    local cancelled = false
    local async = vim.async
    if async then
        local task = async.run(function()
            for _, session in ipairs(result.sessions) do
                if async.is_closing() then
                    return
                end
                add_agents(result, session)
                async.sleep(0)
            end
            if not async.is_closing() then
                callback(result)
            end
        end)
        return function()
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

        add_agents(result, session)
        vim.schedule(step)
    end

    vim.schedule(step)
    return function()
        cancelled = true
    end
end

return M
