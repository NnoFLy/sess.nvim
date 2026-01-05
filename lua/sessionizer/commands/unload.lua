local logger = require("sessionizer.logger")
local state = require("sessionizer.state")
local opts = require("sessionizer").get_opts()

---@param on_unload sessionizer.OnUnloadOpts | nil
---@return nil
return function(on_unload)
    local current_session = state.get_current_session()
    if current_session == nil then
        logger.info("Session is not loaded")
        return
    end

    state.set_prev_session(current_session)
    state.set_current_session(nil)
    vim.g.sessionizer_current_session = nil

    on_unload = vim.tbl_deep_extend("force", opts.on_unload, on_unload or {})
    if on_unload.custom ~= nil then
        on_unload.custom()
    end

    logger.info("Session " .. current_session.name .. " unloaded")
end
