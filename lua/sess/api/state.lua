local state = require("sess.state")

local M = {}

---@return Sess.Session | nil
function M.current()
    return state.get_current_session()
end

---@return Sess.Session | nil
function M.prev()
    return state.get_prev_session()
end

---@return Sess.Session[]
function M.active()
    return state.get_active_sessions()
end

-- Internal setters used by `api/session.lua`.

---@param session Sess.Session | nil
function M.set_current(session)
    state.set_current_session(session)
end

---@param session Sess.Session | nil
function M.set_prev(session)
    state.set_prev_session(session)
end

---@param session Sess.Session
function M.add_active(session)
    state.add_active_session(session)
end

---@param id Sess.SessionId
function M.remove_active(id)
    state.remove_active_session(id)
end

---@param session Sess.Session
function M.replace(session)
    local current = state.get_current_session()
    if current and current.id == session.id then
        state.set_current_session(session)
    end

    local previous = state.get_prev_session()
    if previous and previous.id == session.id then
        state.set_prev_session(session)
    end

    local active = state.get_active_sessions()
    for i, active_session in ipairs(active) do
        if active_session.id == session.id then
            active[i] = session
        end
    end
end

return M
