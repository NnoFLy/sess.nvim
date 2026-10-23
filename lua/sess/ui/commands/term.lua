local api = require("sess.api")
local log = require("sess.log")

return function(context)
    local command = context.raw_tail
    if command == "" then
        command = nil
    end
    local ok, err, _, diagnostics = api.terminal.launch(command)
    if not ok then
        log.error(err)
        return false
    end
    log.diagnostics(diagnostics)
    return true
end
