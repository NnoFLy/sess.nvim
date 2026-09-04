local api = require("sess.api")
local log = require("sess.log")

---@param ctx Sess.CommandContext
---@return boolean
return function(ctx)
    local previous = api.state.prev()
    if not previous then
        log.error("No previous session")
        return false
    end

    local ok, err = api.session.load(previous)
    if not ok then
        log.error(err or "Can't load previous session")
        return false
    end

    return true
end
