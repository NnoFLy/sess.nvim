local M = {}

---@class State
---@field prev_session Session | nil
---@field session_is_loaded boolean
M._state = {
    prev_session = nil,
    session_is_loaded = false,
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

---@param session_is_loaded boolean
---@return nil
function M.set_session_is_loaded(session_is_loaded)
    M._state.session_is_loaded = session_is_loaded
end

---@return boolean
function M.is_session_loaded()
    return M._state.session_is_loaded
end

return M
