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

---@param session Sess.Session
---@return nil
function M.add_active_session(session)
    for i, active in ipairs(M._state.active_sessions) do
        if active.id == session.id then
            M._state.active_sessions[i] = vim.deepcopy(session)
            return
        end
    end

    table.insert(M._state.active_sessions, vim.deepcopy(session))
end

---@param session_id Sess.SessionId
---@return nil
function M.remove_active_session(session_id)
    for i = #M._state.active_sessions, 1, -1 do
        if M._state.active_sessions[i].id == session_id then
            table.remove(M._state.active_sessions, i)
        end
    end
end

---@param session Sess.Session | nil
---@return nil
function M.set_prev_session(session)
    M._state.prev_session = session and vim.deepcopy(session) or nil
end

---@return Sess.Session | nil
function M.get_prev_session()
    return M._state.prev_session and vim.deepcopy(M._state.prev_session) or nil
end

---@param session Sess.Session | nil
---@return nil
function M.set_current_session(session)
    M._state.current_session = session and vim.deepcopy(session) or nil
    vim.g.sess_current_session = session and session.metadata.name or nil
end

---@return Sess.Session | nil
function M.get_current_session()
    return M._state.current_session and vim.deepcopy(M._state.current_session) or nil
end

---@return Sess.Session[]
function M.get_active_sessions()
    return vim.deepcopy(M._state.active_sessions)
end

return M
