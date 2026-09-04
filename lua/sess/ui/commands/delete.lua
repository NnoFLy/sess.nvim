local api = require("sess.api")
local log = require("sess.log")

---@param ctx Sess.CommandContext
---@return boolean
return function(ctx)
    local target = ctx.args[1]
    local ok, err, item = api.session.resolve(target)
    if not ok then
        log.error(err or "Session was not found")
        return false
    end

    local choice = vim.fn.confirm(
        "Delete session " .. item.metadata.name .. "?",
        "&Yes\n&No",
        2
    )
    if choice ~= 1 then
        return true
    end

    local deleted, delete_err = api.session.delete(item)
    if not deleted then
        log.error(delete_err or "Failed to delete session")
        return false
    end

    log.info("Session deleted: " .. item.metadata.name)
    return true
end
