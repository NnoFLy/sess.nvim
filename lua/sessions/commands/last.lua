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

---@param load_opts BeforeLoadOpts | nil
---@return nil
function M._open_last(load_opts)
    local commands = require("sessions.commands")
    local utils = require("sessions.utils")

    local current_session = commands.get.current()
    if current_session.name == prev_session.name then
        utils.notify("Session is the same as previous session", vim.log.levels.WARN)
        return
    end

    if not commands.load(prev_session.name, load_opts) then
        return
    end
end

---@param load_opts BeforeLoadOpts | nil
---@return nil
function M.open_last(load_opts)
    local utils = require("sessions.utils")

    if not prev_session or not prev_session.name then
        utils.notify("No previous session", vim.log.levels.ERROR)
        return
    end

    require("sessions.commands").save()
    M._open_last(load_opts)
end

return M
