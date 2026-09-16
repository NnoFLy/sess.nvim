local api = require("sess.api")
local log = require("sess.log")

---@param ctx Sess.CommandContext
---@return boolean
return function(ctx)
    local target = ctx.args[1]
    if target == nil and api.state.current() == nil then
        log.info("Session is not loaded")

        return false
    end

    local ok, err, item, diagnostics = require("sess.ui.unload")(target)
    if not ok then
        if err == "unload cancelled" then
            log.info("Unload cancelled")
        else
            log.error(err or "Failed to unload session")
        end

        return false
    end

    log.diagnostics(diagnostics)
    log.info("Session " .. item.metadata.name .. " unloaded")

    return true
end
