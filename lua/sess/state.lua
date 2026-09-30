local M = {}

-- This module alone owns mutable runtime records. All reads and writes copy.
local state = { active_sessions = {}, agents_by_session = {}, focused_agents = {} }
local views = {}

function M.get_view(id)
    return views[id] and vim.deepcopy(views[id]) or nil
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
            return
        end
    end

    table.insert(state.active_sessions, vim.deepcopy(session))
end

function M.remove_active_session(id)
    for i = #state.active_sessions, 1, -1 do
        if state.active_sessions[i].id == id then
            table.remove(state.active_sessions, i)
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
end

function M.get_current_session()
    return state.current_session and vim.deepcopy(state.current_session) or nil
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
    if state.focused_agents[session_id] == agent_id then
        state.focused_agents[session_id] = nil
    end
    if next(agents) == nil then
        state.agents_by_session[session_id] = nil
    end
    return agent
end

function M.get_focused_agent_id(session_id)
    return state.focused_agents[session_id]
end

function M.set_focused_agent(session_id, agent_id)
    state.focused_agents[session_id] = agent_id
end

function M.remove_agents(session_id)
    state.agents_by_session[session_id] = nil
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
        end
    end
end

return M
