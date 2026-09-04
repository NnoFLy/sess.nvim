local api = require("sess.api")
local log = require("sess.log")

---@param ctx Sess.CommandContext
---@return boolean
return function(ctx)
    local target = ctx.args[1]
    if target == nil and not api.state.current() then
        local ok, err = api.session.save(vim.fn.getcwd())
        if not ok then
            log.error(err or "Failed to create current session")
            return false
        end
        target = nil
    end

    local ok, err, item = api.session.toggle_pin(target)
    if not ok then
        log.error(err or "Failed to toggle session pin")
        return false
    end

    log.info(item.metadata.pinned and "Session pinned: " .. item.metadata.name
        or "Session unpinned: " .. item.metadata.name)
    return true
end
