local M = {}

---@class Sess.State
---@field prev_session Sess.Session | nil
---@field current_session Sess.Session | nil
M._state = {
    prev_session = nil,
    current_session = nil,
}

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
