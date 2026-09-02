---@param before_load_opts Sess.BeforeLoadOpts | nil
---@param after_load_opts Sess.AfterLoadOpts | nil
---@return boolean
return function(before_load_opts, after_load_opts)
    local commands = require("sess.commands")
    local log = require("sess.log")
    local state = require("sess.state")

    local previous_session = state.get_prev_session()
    if not previous_session then
        log.error("No previous session")
        return false
    end

    if not commands.load(previous_session, before_load_opts, after_load_opts) then
        return false
    end

    return true
end
