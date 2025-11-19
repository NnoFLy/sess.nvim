local M = {}

local logger = require("sessionizer.logger")

---@param s Session
---@return nil
function M.delete_session(s)
    if not s then
        logger.error("No session found")
        return
    end

    local user_input = vim.fn.input("Are you sure you want to delete session " .. s.name .. "? (y/N): ")
    if user_input ~= "y" then
        return
    end

    require("sessionizer.session").delete(s)

    logger.info("Session deleted: " .. s.name)
end

return M
