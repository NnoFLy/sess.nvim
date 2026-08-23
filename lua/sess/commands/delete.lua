local logger = require("sess.logger")
local state = require("sess.state")
local session = require("sess.session")

---@param s Sess.Session
---@param on_unload Sess.OnUnloadOpts | nil
---@return boolean
return function(s, on_unload)
    local opts = require("sess").get_opts()

    if not s then
        logger.error("Session is not provided")
        return false
    end

    if s.last_used == 0 then
        logger.error("Session was not used: " .. s.name)
        return false
    end

    if not session.get.by_path(s.path) then
        logger.error("Session was not found: " .. s.name)
        return false
    end

    local user_input = vim.fn.input("Are you sure you want to delete session " .. s.name .. "? (y/N): ")
    if user_input ~= "y" then
        return true
    end

    local ok = require("sess.session").delete(s)
    if not ok then
        logger.error("Failed to delete session")
        return false
    end

    local current_session = state.get_current_session()
    if current_session and s.path == current_session.path then
        state.set_current_session(nil)
        vim.g.sess_current_session = nil
    end

    on_unload = vim.tbl_deep_extend("force", opts.on_unload, on_unload or {})
    if on_unload.custom ~= nil then
        on_unload.custom()
    end

    logger.info("Session deleted: " .. s.name)

    return true
end
