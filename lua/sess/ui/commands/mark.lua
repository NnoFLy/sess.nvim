local log = require("sess.log")
local marks = require("sess.ui.marks")

return function(ctx)
    local mark, err = marks.parse(ctx.args[1], true)
    if not mark then
        log.error(err)
        return false
    end
    local target = ctx.args[2]
    local ok, assign_err, _, diagnostics = marks.assign(target, mark)
    if not ok then
        return marks.report(false, assign_err)
    end
    log.diagnostics(diagnostics)
    log.info("Set mark @" .. mark)
    return true
end
