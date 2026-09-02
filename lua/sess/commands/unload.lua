local log = require("sess.log")
local state = require("sess.state")

---@param on_unload Sess.OnUnloadOpts | nil
---@return nil
return function(on_unload)
    local opts = require("sess").get_opts()

    local current_session = state.get_current_session()
    if current_session == nil then
        log.info("Session is not loaded")
        return
    end

    state.set_prev_session(current_session)
    state.set_current_session(nil)

    on_unload = vim.tbl_deep_extend("force", opts.on_unload, on_unload or {})
    if on_unload.custom ~= nil then
        on_unload.custom()
    end

    state.remove_active_session(current_session.id)

    log.info("Session " .. current_session.metadata.name .. " unloaded")
end
