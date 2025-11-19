local M = {}

---@param load_opts BeforeLoadOpts | nil
---@return boolean
function M.open_last(load_opts)
    local session = require("sessions.session")
    local commands = require("sessions.commands")
    local previous_session = require("sessions.state").get_prev_session()
    local logger = require("sessions.logger")

    if not previous_session or not previous_session.name then
        logger.error("No previous session")
        return false
    end

    commands.save()
    local current_session = session.get.current()
    if current_session and current_session.name == previous_session.name then
        logger.warn("Session is the same as previous session")
        return false
    end

    if not commands.load(previous_session.name, load_opts) then
        return false
    end

    return true
end

return M
