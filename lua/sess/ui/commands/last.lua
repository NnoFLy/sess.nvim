local api = require("sess.api")
local log = require("sess.log")

---@param ctx Sess.CommandContext
---@return boolean
return function(ctx)
    local ok, err, _, diagnostics = api.session.last()
    if not ok then
        if err == "no previous session" then
            err = "No previous session"
        end

        log.error(err or "Can't load previous session")

        return false
    end

    log.diagnostics(diagnostics)

    return true
end
