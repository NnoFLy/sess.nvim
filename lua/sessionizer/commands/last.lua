---@param before_load_opts BeforeLoadOpts | nil
---@param after_load_opts AfterLoadOpts | nil
---@return boolean
return function(before_load_opts, after_load_opts)
    local commands = require("sessionizer.commands")
    local logger = require("sessionizer.logger")
    local state = require("sessionizer.state")

    local previous_session = state.get_prev_session()
    if not previous_session then
        logger.error("No previous session")
        return false
    end

    if not commands.load(previous_session, before_load_opts, after_load_opts) then
        return false
    end

    return true
end
