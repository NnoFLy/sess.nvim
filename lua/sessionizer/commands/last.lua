local M = {}

---@param before_load_opts BeforeLoadOpts | nil
---@param after_load_opts AfterLoadOpts | nil
---@return boolean
function M.open_last(before_load_opts, after_load_opts)
    local session = require("sessionizer.session")
    local commands = require("sessionizer.commands")
    local previous_session = require("sessionizer.state").get_prev_session()
    local logger = require("sessionizer.logger")

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

    if not commands.load(previous_session, before_load_opts, after_load_opts) then
        return false
    end

    return true
end

return M
