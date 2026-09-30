local agents = require("sess.api.agent")
local sessions = require("sess.api.session")
local state = require("sess.api.state")

local M = {}

-- Compose the active-session view once at the application boundary. UI
-- adapters receive a stable, read-only snapshot instead of making N+1 calls.
function M.snapshot()
    local active = state.active()
    local result = {
        sessions = active,
        agents_by_id = {},
        focused_by_id = {},
        marks_by_id = {},
        current_id = state.current() and state.current().id or nil,
        diagnostics = {},
    }

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

    for _, session in ipairs(active) do
        local listed, list_err, found, agent_diagnostics = agents.list(session.id)
        if not listed then result.diagnostics[#result.diagnostics + 1] = list_err end
        for _, diagnostic in ipairs(agent_diagnostics or {}) do result.diagnostics[#result.diagnostics + 1] = diagnostic end
        result.agents_by_id[session.id] = found or {}

        local focused_ok, focused_err, focused = agents.focused(session.id)
        if not focused_ok and focused_err then result.diagnostics[#result.diagnostics + 1] = focused_err end
        result.focused_by_id[session.id] = focused and focused.id or nil
    end

    return result
end

return M
