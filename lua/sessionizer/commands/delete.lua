local M = {}

local logger = require("sessionizer.logger")

---@param s Session
---@return boolean
function M.delete_session(s)
    if not s then
        logger.error("No session found")
        return false
    end

    local user_input = vim.fn.input("Are you sure you want to delete session " .. s.name .. "? (y/N): ")
    if user_input ~= "y" then
        return false
    end

    local ok = require("sessionizer.session").delete(s)

    logger.info("Session deleted: " .. s.name)

    return ok
end

return M
