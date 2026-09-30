local catalog = require("sess.session")
local editor = require("sess.editor")
local state = require("sess.state")
local observer = require("sess.lifecycle.observer")
local opts = require("sess.api.opts")
local target = require("sess.lifecycle.target")
local transaction = require("sess.lifecycle.transaction")

local M = {}

function M.restore(destination, options)
    local callbacks, hook_err = observer.hooks(options)
    if not callbacks then
        return false, hook_err
    end

    local entry, err = catalog.resolve_deleted(destination)
    if not entry then
        return false, err
    end

    local item = { id = entry.id, metadata = entry.metadata }
    local ready, pre_err = observer.before("restore", item, callbacks)
    if not ready then
        return false, pre_err
    end

    local fresh_entry, resolve_err = catalog.resolve_deleted(entry.key)
    if not fresh_entry then
        return false, resolve_err
    end

    local restored, restore_err = catalog.restore(fresh_entry.key)
    if not restored then
        return false, restore_err
    end

    return observer.finish("restore", restored, callbacks)
end

function M.delete(destination, options)
    local callbacks, hook_err = observer.hooks(options)
    if not callbacks then
        return false, hook_err
    end

    local item, err = target.resolve(destination)
    if not item then
        return false, err
    end

    local current = state.get_current_session()
    local is_current = current and current.id == item.id
    if is_current then
        local ready, pre_err = observer.before("delete", item, callbacks)
        if not ready then
            return false, pre_err
        end

        item, err = target.resolve(item)
        if not item then
            return false, err
        end
    end

    local changed, change_err
    if is_current then
        changed, change_err = transaction.change(function()
            editor.empty(vim.fn.getcwd())
            local ok, delete_err = catalog.delete(item.id)
            if not ok then
                error(delete_err)
            end
        end)
    else
        changed, change_err = catalog.delete(item.id)
    end

    if not changed then
        return false, change_err
    end

    if is_current then
        state.set_current_session(nil)
    end

    local previous = state.get_prev_session()
    if previous and previous.id == item.id then
        state.set_prev_session(nil)
    end

    state.remove_active_session(item.id)
    state.set_view(item.id, nil)
    state.remove_agents(item.id)

    local diagnostics = {}
    if is_current then
        local _, _, _, unload_diagnostics = observer.finish("unload", item, callbacks)
        diagnostics = unload_diagnostics
    end

    return observer.finish("delete", item, callbacks, diagnostics)
end

function M.rename(destination, name)
    if type(name) ~= "string" or vim.trim(name) == "" then
        return false, "session name cannot be empty"
    end

    local item, err = target.resolve(destination)
    if not item then
        return false, err
    end

    local renamed, rename_err = catalog.rename(item.id, name)
    if not renamed then
        return false, rename_err
    end

    state.replace(renamed)
    return observer.finish("rename", renamed, opts.get().hooks)
end

function M.toggle_pin(destination)
    local item, err = target.resolve(destination)
    if not item then
        return false, err
    end

    local updated, pin_err = catalog.toggle_pinned(item.id)
    if not updated then
        return false, pin_err
    end

    state.replace(updated)
    return observer.finish("pin", updated, opts.get().hooks)
end

return M
