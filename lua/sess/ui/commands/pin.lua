local api = require("sess.api")
local log = require("sess.log")

return function(ctx)
    local ok, err, item, diagnostics = api.session.toggle_pin(ctx.args[1])
    if not ok then
        log.error(err)

        return false
    end

    log.diagnostics(diagnostics)
    log.info(
        item.metadata.pinned and "Session pinned: " .. item.metadata.name
            or "Session unpinned: " .. item.metadata.name
    )

    return true
end
