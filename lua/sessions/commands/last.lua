local M = {}

---@type Session
M.prev_session = nil

---@param session Session
---@return nil
function M.set_prev_session(session)
    M.prev_session = session
end

---@return Session
function M.get_prev_session()
    return M.prev_session
end

---@param load_opts BeforeLoadOpts | nil
---@return boolean
function M.open_last(load_opts)
    local session = require("sessions.session")
    local commands = require("sessions.commands")
    local utils = require("sessions.utils")
    local ps = M.get_prev_session()

    if not M.prev_session or not ps.name then
        utils.notify("No previous session", vim.log.levels.ERROR)
        return false
    end

    commands.save()
    local current_session = session.get.current()
    if current_session and current_session.name == ps.name then
        utils.notify("Session is the same as previous session", vim.log.levels.WARN)
        return false
    end

    if not commands.load(ps.name, load_opts) then
        return false
    end

    return true
end

return M
