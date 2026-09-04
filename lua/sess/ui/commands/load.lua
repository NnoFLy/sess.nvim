local api = require("sess.api")
local log = require("sess.log")
local usecase = require("sess.usecase")

---@param ctx Sess.CommandContext
---@return boolean
return function(ctx)
    local target = ctx.args[1]
    local ok, err, item, before_load, after_load = api.session.prepare(target)
    if not ok then
        log.error(err or "Can't load session")
        return false
    end

    local current = api.state.current()
    if current and current.id == item.id then
        log.info("Session is already loaded: " .. item.metadata.name)
        return true
    end

    if current then
        local saved, save_err = api.session.save(current)
        if not saved then
            log.error("Can't load session: failed to save the current session: " .. tostring(save_err))
            return false
        end
    else
        local to_save, save_err = usecase.do_u_wanna_save()
        if save_err then
            log.error(save_err)
            return false
        end
        if to_save then
            local saved, save_current_err = api.session.save(to_save)
            if not saved then
                log.error("Can't load session: failed to save the current session: " .. tostring(save_current_err))
                return false
            end
        end
    end

    local loaded, load_err, loaded_item = api.session.commit(item, {
        before_load = before_load,
        after_load = after_load,
    })
    if not loaded then
        log.error(load_err or "Can't load session")
        return false
    end

    log.info("Current session: " .. loaded_item.metadata.name)
    return true
end
