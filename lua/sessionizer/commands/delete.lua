local logger = require("sessionizer.logger")
local state = require("sessionizer.state")

---@param s sessionizer.Session
---@return boolean
return function(s)
    if not s then
        logger.error("No session found")
        return false
    end

    local user_input = vim.fn.input("Are you sure you want to delete session " .. s.name .. "? (y/N): ")
    if user_input ~= "y" then
        return false
    end

    local ok = require("sessionizer.session").delete(s)

    if not ok then
        logger.error("Failed to delete session")
        return false
    end

    if s.path == state.get_current_session().path then
        state.set_current_session(nil)
    end

    logger.info("Session deleted: " .. s.name)

    return true
end
