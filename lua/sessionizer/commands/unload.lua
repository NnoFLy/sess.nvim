local logger = require("sessionizer.logger")
local state = require("sessionizer.state")

---@return nil
return function()
    local current_session = state.get_current_session()
    if current_session == nil then
        logger.info("Session is not loaded")
        return
    end
    state.set_prev_session(current_session)
    state.set_current_session(nil)
    vim.g.sessionizer_current_session = nil
    logger.info("Session " .. current_session.name .. " unloaded")
end
