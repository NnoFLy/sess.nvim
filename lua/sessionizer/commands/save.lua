---@return boolean
return function()
    local session = require("sessionizer.session")
    local logger = require("sessionizer.logger")
    local state = require("sessionizer.state")

    local current_session = state.get_current_session()
    if current_session == nil then
        current_session = session.get.by_path(vim.fn.getcwd())
    end
    local session_name = current_session and current_session.name or nil

    local s = session.new(session_name)
    if not session.save(s) then
        logger.error("Failed to save session")
        return false
    end

    if state.get_current_session() == nil then
        state.set_current_session(s)
    end

    return true
end
