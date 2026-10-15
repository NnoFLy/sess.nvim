local M = {}

-- This module alone owns mutable runtime records. All reads and writes copy.
local state = {
    active_sessions = {},
    agents_by_session = {},
    -- Sequenced integration reports are deliberately kept apart from agent
    -- records and views. They are process-local runtime state and therefore
    -- cannot accidentally enter a persisted session snapshot.
    agent_reports_by_session = {},
    -- Rejected report metadata is bounded runtime-only context for explain().
    agent_report_rejections = {},
    focused_agents = {},
    active_generation = 0,
}
local views = {}

local function bump_active_generation()
    state.active_generation = state.active_generation + 1
end

function M.get_view(id)
    return views[id] and vim.deepcopy(views[id]) or nil
end

-- Narrow read helpers for high-frequency runtime queries. Keep the full view
-- defensive-copying API above for callers that need the complete record.
function M.get_view_buffers(id)
    local view = views[id]
    return vim.tbl_keys(view and view.buffers or {})
end

function M.is_current_session(id)
    return state.current_session ~= nil and state.current_session.id == id
end

function M.set_view(id, view)
    views[id] = view and vim.deepcopy(view) or nil
end

function M.get_views()
    return vim.deepcopy(views)
end

function M.add_active_session(session)
    for i, active in ipairs(state.active_sessions) do
        if active.id == session.id then
            state.active_sessions[i] = vim.deepcopy(session)
            bump_active_generation()
            return
        end
    end

    table.insert(state.active_sessions, vim.deepcopy(session))
    bump_active_generation()
end

function M.remove_active_session(id)
    for i = #state.active_sessions, 1, -1 do
        if state.active_sessions[i].id == id then
            table.remove(state.active_sessions, i)
            bump_active_generation()
        end
    end
end

function M.set_prev_session(session)
    state.prev_session = session and vim.deepcopy(session) or nil
end

function M.get_prev_session()
    return state.prev_session and vim.deepcopy(state.prev_session) or nil
end

function M.set_current_session(session)
    state.current_session = session and vim.deepcopy(session) or nil
    vim.g.sess_current_session = session and session.metadata.name or nil
    bump_active_generation()
end

function M.get_active_generation()
    return state.active_generation
end

function M.get_current_session()
    return state.current_session and vim.deepcopy(state.current_session) or nil
end

function M.get_current_session_id()
    return state.current_session and state.current_session.id or nil
end

function M.get_active_sessions()
    return vim.deepcopy(state.active_sessions)
end

function M.get_agents(id)
    local agents = state.agents_by_session[id] or {}
    local result = {}
    for agent_id, agent in pairs(agents) do
        result[agent_id] = vim.deepcopy(agent)
    end
    return result
end

function M.set_agent(session_id, agent)
    state.agents_by_session[session_id] = state.agents_by_session[session_id] or {}
    state.agents_by_session[session_id][agent.id] = vim.deepcopy(agent)
end

function M.remove_agent(session_id, agent_id)
    local agents = state.agents_by_session[session_id]
    if not agents or not agents[agent_id] then
        return nil
    end
    local agent = vim.deepcopy(agents[agent_id])
    agents[agent_id] = nil
    local reports = state.agent_reports_by_session[session_id]
    if reports then
        reports[agent_id] = nil
        if next(reports) == nil then state.agent_reports_by_session[session_id] = nil end
    end
    local rejections = state.agent_report_rejections[session_id]
    if rejections then
        rejections[agent_id] = nil
        if next(rejections) == nil then state.agent_report_rejections[session_id] = nil end
    end
    if state.focused_agents[session_id] == agent_id then
        state.focused_agents[session_id] = nil
    end
    if next(agents) == nil then
        state.agents_by_session[session_id] = nil
    end
    return agent
end

function M.get_agent_reports(session_id, agent_id)
    local reports = state.agent_reports_by_session[session_id]
    reports = reports and reports[agent_id] or {}
    return vim.deepcopy(reports)
end

-- Reports belong to a terminal job incarnation. Drop reports from replaced
-- jobs before scanning or accepting new sources so runtime-only state remains
-- bounded across repeated terminal reuse.
function M.prune_agent_reports(session_id, agent_id, job_id)
    if job_id == nil then return end
    local by_agent = state.agent_reports_by_session[session_id]
    local reports = by_agent and by_agent[agent_id]
    if not reports then return end
    for source, report in pairs(reports) do
        if type(report) ~= "table" or report.job_id ~= job_id then reports[source] = nil end
    end
    if next(reports) ~= nil then return end
    by_agent[agent_id] = nil
    if next(by_agent) == nil then state.agent_reports_by_session[session_id] = nil end
end

function M.set_agent_report(session_id, agent_id, source, report)
    state.agent_reports_by_session[session_id] = state.agent_reports_by_session[session_id] or {}
    local reports = state.agent_reports_by_session[session_id]
    reports[agent_id] = reports[agent_id] or {}
    reports[agent_id][source] = vim.deepcopy(report)
end

function M.record_agent_report_rejection(session_id, agent_id, rejection)
    state.agent_report_rejections[session_id] = state.agent_report_rejections[session_id] or {}
    local rejections = state.agent_report_rejections[session_id]
    rejections[agent_id] = rejections[agent_id] or {}
    local entries = rejections[agent_id]
    entries[#entries + 1] = vim.deepcopy(rejection)
    -- Explain only needs recent bounded context; rejected input never gets to
    -- grow this process-local record indefinitely.
    if #entries > 8 then table.remove(entries, 1) end
end

function M.get_agent_report_rejections(session_id, agent_id)
    local rejections = state.agent_report_rejections[session_id]
    return vim.deepcopy(rejections and rejections[agent_id] or {})
end

function M.remove_agent_reports(session_id, agent_id)
    local reports = state.agent_reports_by_session[session_id]
    if reports then
        reports[agent_id] = nil
        if next(reports) == nil then state.agent_reports_by_session[session_id] = nil end
    end
    local rejections = state.agent_report_rejections[session_id]
    if rejections then
        rejections[agent_id] = nil
        if next(rejections) == nil then state.agent_report_rejections[session_id] = nil end
    end
end

function M.get_focused_agent_id(session_id)
    return state.focused_agents[session_id]
end

function M.set_focused_agent(session_id, agent_id)
    state.focused_agents[session_id] = agent_id
end

function M.remove_agents(session_id)
    state.agents_by_session[session_id] = nil
    state.agent_reports_by_session[session_id] = nil
    state.agent_report_rejections[session_id] = nil
    state.focused_agents[session_id] = nil
end

function M.replace(session)
    if state.current_session and state.current_session.id == session.id then
        M.set_current_session(session)
    end

    if state.prev_session and state.prev_session.id == session.id then
        M.set_prev_session(session)
    end

    for i, active in ipairs(state.active_sessions) do
        if active.id == session.id then
            state.active_sessions[i] = vim.deepcopy(session)
            bump_active_generation()
        end
    end
end

return M
