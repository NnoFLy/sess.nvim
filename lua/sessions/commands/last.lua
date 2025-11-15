local M = {}

---@type Session
local prev_session = nil

---@param session Session
---@return nil
function M.set_prev_session(session)
    prev_session = session
end

---@return Session
function M.get_prev_session()
    return prev_session
end

---@return nil
function M._open_last()
    local commands = require("sessions.commands")

    local current_session = commands.get.current()
    if current_session.name == prev_session.name then
        vim.notify("Session is the same as previous session", vim.log.levels.WARN)
        return
    end

    if not commands.load(prev_session.name) then
        return
    end
end

---@return nil
function M.open_last()
    if not prev_session or not prev_session.name then
        vim.notify("No previous session", vim.log.levels.ERROR)
        return
    end

    require("sessions.commands").save()
    M._open_last()
end

return M
