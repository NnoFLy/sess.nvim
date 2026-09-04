local api = require("sess.api")
local log = require("sess.log")

---@param ctx Sess.CommandContext
---@return boolean
return function(ctx)
    local current = api.state.current()
    if current == nil then
        log.info("Session is not loaded")
        return false
    end

    local ok, err = api.session.unload()
    if not ok then
        log.error(err or "Failed to unload session")
        return false
    end

    log.info("Session " .. current.metadata.name .. " unloaded")
    return true
end
