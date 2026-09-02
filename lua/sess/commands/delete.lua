local log = require("sess.log")
local state = require("sess.state")
local session = require("sess.session")

---@param s Sess.Session | Sess.SessionId
---@param on_unload Sess.OnUnloadOpts | nil
---@return boolean
return function(s, on_unload)
    local opts = require("sess").get_opts()

    if not s then
        log.error("Session was not provided")
        return false
    end

    if type(s) == "string" then
        local resolved, err = session.get(s)
        if not resolved then
            log.error(err or "Session was not found")
            return false
        end
        s = resolved
    end

    local choice = vim.fn.confirm(
        "Delete session " .. s.metadata.name .. "?",
        "&Yes\n&No",
        2
    )
    if choice ~= 1 then
        return true
    end

    local ok, err = session.delete(s.id)
    if not ok then
        log.error(err or "Failed to delete session")
        return false
    end

    local current_session = state.get_current_session()
    if current_session and s.id == current_session.id then
        state.set_current_session(nil)
    end

    on_unload = vim.tbl_deep_extend("force", opts.on_unload, on_unload or {})
    if on_unload.custom ~= nil then
        on_unload.custom()
    end

    log.info("Session deleted: " .. s.metadata.name)
    return true
end
