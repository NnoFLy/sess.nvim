local M = {}

---@param s Session | nil
---@return nil
function M.delete_session(s)
    local session = require("sessions.session")
    local logger = require("sessions.logger")

    s = s or session.get.current()

    if not s then
        logger.error("Session not found")
        return
    end

    local user_input = vim.fn.input("Are you sure you want to delete session " .. s.name .. "? (y/N): ")
    if user_input ~= "y" then
        return
    end

    require("sessions.session").delete(s)

    logger.info("Session deleted: " .. s.name)
end

return M
