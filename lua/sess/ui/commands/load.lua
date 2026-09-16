local api = require("sess.api")
local log = require("sess.log")

return function(ctx)
    local ok, err, item, diagnostics = api.session.load(ctx.args[1])
    if not ok then
        log.error(err)

        return false
    end

    log.diagnostics(diagnostics)
    log.info("Current session: " .. item.metadata.name)

    return true
end
