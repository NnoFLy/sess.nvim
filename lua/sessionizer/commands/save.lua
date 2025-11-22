---@return boolean
return function()
    local session = require("sessionizer.session")
    local logger = require("sessionizer.logger")
    local state = require("sessionizer.state")

    local current_session = state.get_current_session()
    local session_name = current_session and current_session.name

    local s = session.new(session_name)
    if not session.save(s) then
        logger.error("Failed to save session")
        return false
    end

    if not current_session then
        state.set_current_session(s)
    end

    return true
end
