local M = {}

---@return boolean
function M.save_session()
    local session = require("sessions.session")
    local logger = require("sessions.logger")

    local current_session = session.get.current()
    local session_name
    if current_session then
        session_name = current_session.name
    end

    local s = session.new(session_name)
    if not session.save(s) then
        logger.error("Failed to save session")
        return false
    end
    return true
end

return M
