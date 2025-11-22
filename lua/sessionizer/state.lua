local M = {}

---@class State
---@field prev_session Session | nil
---@field current_session Session | nil
M._state = {
    prev_session = nil,
    current_session = nil,
}

---@param session Session
---@return nil
function M.set_prev_session(session)
    M._state.prev_session = session
end

---@return Session
function M.get_prev_session()
    return M._state.prev_session
end

---@param session Session | nil
---@return nil
function M.set_current_session(session)
    M._state.current_session = session
end

---@return Session | nil
function M.get_current_session()
    return M._state.current_session
end

return M
