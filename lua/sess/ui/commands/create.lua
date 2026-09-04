local api = require("sess.api")
local log = require("sess.log")
local usecase = require("sess.usecase")

---@param ctx Sess.CommandContext
---@return boolean
return function(ctx)
    local path = ctx.args[1]
    local cwd = path and vim.trim(path) ~= "" and vim.fs.normalize(path) or vim.fn.getcwd()

    local found, lookup_err, existing = api.session.get_by_path(cwd)
    if not found then
        log.error(lookup_err or ("Failed to find session for directory: " .. cwd))
        return false
    end
    if existing then
        return require("sess.ui.commands").load({
            args = { existing.id },
            bang = false,
            range_start = 0,
            range_end = 0,
            line1 = 0,
            line2 = 0,
            count = 0,
        })
    end

    if not api.state.current() then
        local to_save, save_err = usecase.do_u_wanna_save()
        if save_err then
            log.error(save_err)
            return false
        end
        if to_save then
            local ok, err = api.session.save(to_save)
            if not ok then
                log.error(err or "Failed to save current session")
                return false
            end
        end
    end

    local ok, err, item = api.session.create(cwd)
    if not ok then
        log.error(err or "Failed to create session")
        return false
    end

    log.info("Session created: " .. item.metadata.name)
    return true
end
