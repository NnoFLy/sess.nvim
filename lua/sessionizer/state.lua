local M = {}

---@class sessionizer.State
---@field prev_session sessionizer.Session | nil
---@field current_session sessionizer.Session | nil
---@field terminals table<string, sessionizer.Terminal[]>
M._state = {
    prev_session = nil,
    current_session = nil,
    terminals = {},
}

---@param session sessionizer.Session
---@return nil
function M.set_prev_session(session)
    M._state.prev_session = session
end

---@return sessionizer.Session
function M.get_prev_session()
    return M._state.prev_session
end

---@param session sessionizer.Session | nil
---@return nil
function M.set_current_session(session)
    M._state.current_session = session
end

---@return sessionizer.Session | nil
function M.get_current_session()
    return M._state.current_session
end

---@param session sessionizer.Session
---@param terminals sessionizer.Terminal[]
---@return nil
function M.set_terminals(session, terminals)
    local current_session = session.path
    M._state.terminals[current_session] = terminals
end

---@param session sessionizer.Session
---@return sessionizer.Terminal[]
function M.get_terminals(session)
    local current_session = session.path
    return M._state.terminals[current_session] or {}
end

return M
