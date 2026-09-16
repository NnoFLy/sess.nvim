local api = require("sess.api")
local log = require("sess.log")

return function(ctx)
    local cwd = ctx.args[1] or vim.fn.getcwd()
    local found, lookup_err, existing = api.session.get_by_path(cwd)
    if not found then
        log.error(lookup_err)

        return false
    end

    local ok, err, item, diagnostics
    if existing then
        ok, err, item, diagnostics = api.session.load(existing)
    else
        ok, err, item, diagnostics = api.session.create(cwd)
    end

    if not ok then
        log.error(err)

        return false
    end

    log.diagnostics(diagnostics)
    log.info("Current session: " .. item.metadata.name)

    return true
end
