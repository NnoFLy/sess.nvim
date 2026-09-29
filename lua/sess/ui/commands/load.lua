local api = require("sess.api")
local log = require("sess.log")
local load_or_create = require("sess.ui.load_or_create")
local path = require("sess.ui.path")

return function(ctx)
    local target = ctx.args[1] or vim.fn.getcwd()
    local ok, err, item, diagnostics
    if path.is_path(target) then
        ok, err, item, diagnostics = load_or_create.run(target)
    else
        ok, err, item, diagnostics = api.session.load(target)
    end
    if not ok then
        log.error(err)

        return false
    end

    log.diagnostics(diagnostics)
    log.info("Current session: " .. item.metadata.name)

    return true
end
