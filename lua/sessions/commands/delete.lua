local M = {}

---@param session_name string | nil
---@return nil
function M.delete_session(session_name)
    local user_input = vim.fn.input("Are you sure you want to delete session " .. session_name .. "? (y/N): ")
    if user_input ~= "y" then
        return
    end

    local session = require("sessions.session")
    local logger = require("sessions.logger")

    local ses
    if not session_name then
        ses = session.get.current()
    else
        ses = session.get.by_name(session_name)
    end

    if not ses then
        logger.error("Session not found")
        return
    end

    require("sessions.session").delete(ses)

    logger.info("Session deleted: " .. ses.name)
end

return M
