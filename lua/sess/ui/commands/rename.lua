local api = require("sess.api")
local log = require("sess.log")

---@param ctx Sess.CommandContext
---@return boolean, string?
return function(ctx)
    local target = ctx.args[1]
    local name = ctx.args[2]
    local ok, err, item = api.session.resolve(target)
    if not ok then
        log.error(err or "Session was not found")
        return false, err
    end

    name = name or vim.fn.input("Enter Session Name: ", item.metadata.name)
    local renamed, rename_err, updated = api.session.rename(item, name)
    if not renamed then
        log.error(rename_err or "Failed to rename session")
        return false, rename_err
    end

    log.info("Session renamed: " .. updated.metadata.name)
    return true
end
