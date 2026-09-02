local M = {}

---@class Sess.State
---@field active_sessions Sess.Session[]
---@field prev_session Sess.Session | nil
---@field current_session Sess.Session | nil
M._state = {
    active_sessions = {},
    prev_session = nil,
    current_session = nil,
}

---@return Sess.Session[]
function M.get_active_sessions()
    return M._state.active_sessions
end

---@param session Sess.Session
function M.add_active_session(session)
    for _, s in pairs(M._state.active_sessions) do
        if s.id == session.id then
            return
        end
    end
    table.insert(M._state.active_sessions, session)
end

---@param session_id Sess.SessionId
function M.remove_active_session(session_id)
    for idx, session in pairs(M._state.active_sessions) do
        if session_id == session.id then
            table.remove(M._state.active_sessions, idx)
        end
    end
end

---@param session Sess.Session
---@return nil
function M.set_prev_session(session)
    M._state.prev_session = session
end

---@return Sess.Session
function M.get_prev_session()
    return M._state.prev_session
end

---@param session Sess.Session | nil
---@return nil
function M.set_current_session(session)
    M._state.current_session = session
    vim.g.sess_current_session = session and session.metadata.name or nil
end

---@return Sess.Session | nil
function M.get_current_session()
    return M._state.current_session
end

return M
