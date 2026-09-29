local log = require("sess.log")
local load_or_create = require("sess.ui.load_or_create")

return function(ctx)
    local cwd = ctx.args[1] or vim.fn.getcwd()
    local ok, err, item, diagnostics = load_or_create.run(cwd)

    if not ok then
        log.error(err)

        return false
    end

    log.diagnostics(diagnostics)
    log.info("Current session: " .. item.metadata.name)

    return true
end
