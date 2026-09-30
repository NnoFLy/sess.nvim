local catalog = require("sess.session")
local editor = require("sess.editor")
local state = require("sess.state")
local observer = require("sess.lifecycle.observer")
local target = require("sess.lifecycle.target")
local rollback = require("sess.lifecycle.editor_rollback")
local save = require("sess.lifecycle.save")
local unload = require("sess.unload")

local M = {}

function M.run(destination, options, context)
    -- Preserve unload({ hooks = ... }) for callers of the current-only API.
    if
        type(destination) == "table"
        and destination.id == nil
        and destination.metadata == nil
        and options == nil
    then
        options, destination = destination, nil
    end

    local callbacks = context.hooks
    if options and options.confirm ~= nil and type(options.confirm) ~= "function" then
        return false, "unload confirm must be a function"
    end

    local item, err = target.resolve(destination)
    if not item then
        return false, err
    end

    local current = state.get_current_session()
    local is_current = current and current.id == item.id
    if not is_current then
        local active = false
        for _, session in ipairs(state.get_active_sessions()) do
            if session.id == item.id then
                active = true
                break
            end
        end

        if not active then
            return true, nil, item, {}
        end
    end

    local ready, pre_err = observer.before("unload", item, callbacks)
    if not ready then
        return false, pre_err
    end

    item, err = target.resolve(item)
    if not item then
        return false, err
    end

    local plan, plan_err = unload.prepare(item, options and options.confirm)
    if not plan then
        return false, plan_err
    end

    item, err = target.resolve(item)
    if not item then
        return false, err
    end

    local saved, save_err = unload.save_buffers(plan)
    if not saved then
        return false, save_err
    end

    local diagnostics = {}
    if is_current then
        saved, save_err, item, diagnostics = save.outgoing(callbacks)
        if not saved then
            return false, save_err
        end
    elseif plan.decision == "save" then
        local view = state.get_view(item.id)
        if view then
            local original = editor.capture()
            local refreshed, refresh_err, refresh_diagnostics = rollback.change(function()
                local restore_diagnostics = editor.restore(view)
                local ok, snapshot_err = save.snapshot(item)
                if not ok then
                    error(snapshot_err)
                end
                vim.list_extend(restore_diagnostics, editor.restore(original))
                return restore_diagnostics
            end)
            if not refreshed then
                return false, "failed to refresh unloaded session: " .. tostring(refresh_err)
            end
            vim.list_extend(diagnostics, refresh_diagnostics or {})
        end
    end

    local valid, validation_err = unload.validate(plan)
    if not valid then
        return false, validation_err
    end

    local function close()
        if is_current then
            editor.empty(vim.fn.getcwd())
        end
        local closed, close_err = unload.close(plan)
        if not closed then
            error(close_err)
        end
    end

    local changed, change_err
    if is_current then
        changed, change_err = rollback.change(close)
    else
        changed, change_err = editor.protected(close)
    end
    if not changed then
        return false, change_err
    end

    if is_current then
        state.set_prev_session(item)
        state.set_current_session(nil)
    end
    state.remove_active_session(item.id)
    state.set_view(item.id, nil)
    state.remove_agents(item.id)

    return observer.finish("unload", item, callbacks, diagnostics)
end

return M
