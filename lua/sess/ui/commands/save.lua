local api = require("sess.api")
local log = require("sess.log")

return function()
    local ok, err, _, diagnostics = api.session.save()
    if not ok then
        log.error(err)

        return false
    end

    log.diagnostics(diagnostics)

    return true
end
