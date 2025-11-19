local M = {}

---@param load_opts BeforeLoadOpts | nil
---@return boolean
function M.open_last(load_opts)
    local session = require("sessions.session")
    local commands = require("sessions.commands")
    local utils = require("sessions.utils")
    local previous_session = require("sessions.state").get_prev_session()

    if not previous_session or not previous_session.name then
        utils.notify("No previous session", vim.log.levels.ERROR)
        return false
    end

    commands.save()
    local current_session = session.get.current()
    if current_session and current_session.name == previous_session.name then
        utils.notify("Session is the same as previous session", vim.log.levels.WARN)
        return false
    end

    if not commands.load(previous_session.name, load_opts) then
        return false
    end

    return true
end

return M
