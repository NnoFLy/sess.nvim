local log = require("sess.log")
local session = require("sess.session")
local state = require("sess.state")

---@return boolean
return function()
    local current = state.get_current_session()
    if current then
        local ok, err = session.save(current.id)
        if not ok then
            log.error("Failed to save session: " .. tostring(err))
            return false
        end
        local updated = session.get(current.id)
        if updated then
            state.set_current_session(updated)
        end
        return true
    end

    local existing, err = session.get_by_path(vim.fn.getcwd())
    if err then
        log.error("Failed to find session: " .. tostring(err))
        return false
    end

    if existing then
        local ok, save_err = session.save(existing.id)
        if not ok then
            log.error("Failed to save session: " .. tostring(save_err))
            return false
        end
        state.set_current_session(session.get(existing.id))
        return true
    end

    local created, create_err = session.create({ cwd = vim.fn.getcwd() })
    if not created then
        log.error("Failed to create session: " .. tostring(create_err))
        return false
    end

    state.set_current_session(created)
    return true
end
