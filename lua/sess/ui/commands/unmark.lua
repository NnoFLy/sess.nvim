local api = require("sess.api")
local log = require("sess.log")
local marks = require("sess.ui.marks")

return function(ctx)
    local mark, err = marks.parse(ctx.args[1], true)
    if not mark then
        log.error(err)
        return false
    end
    local ok, clear_err, _, diagnostics = api.session.clear_mark(mark)
    if not ok then
        log.error(clear_err)
        return false
    end
    log.diagnostics(diagnostics)
    log.info("Removed mark @" .. mark)
    return true
end
