local api = require("sess.api")
local log = require("sess.log")

---@param ctx Sess.CommandContext
---@return boolean
return function(ctx)
    local target = ctx.args[1]
    target = target or (api.state.current() and nil or vim.fn.getcwd())

    local ok, err = api.session.save(target)
    if not ok then
        log.error("Failed to save session: " .. tostring(err))
        return false
    end

    return true
end
