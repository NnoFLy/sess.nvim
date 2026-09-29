local api = require("sess.api")
local log = require("sess.log")

return function(context)
    if #context.args == 0 then
        local ok, telescope = pcall(require, "sess.ui.telescope")
        if not ok then
            log.error("You need to install telescope.nvim for this command")
            return false
        end
        return telescope.restore()
    end

    local ok, err, _, diagnostics = api.session.restore(context.args[1])
    if not ok then
        log.error(err or "Failed to restore session")
        return false
    end
    log.diagnostics(diagnostics)
    log.info("Session restored")
    return true
end
