local catalog = require("sess.session")
local editor = require("sess.editor")
local storage = require("sess.storage")
local state = require("sess.state")
local observer = require("sess.lifecycle.observer")
local save = require("sess.lifecycle.save")
local target = require("sess.lifecycle.target")
local rollback = require("sess.lifecycle.editor_rollback")
local commit = require("sess.lifecycle.commit")

local M = {}

function M.run(destination, options, context)
    local callbacks = context.hooks

    local item, err, lookup_diagnostics
    if destination == nil then
        item, err, lookup_diagnostics = catalog.get_by_path(vim.fn.getcwd())
    else
        local _reason
        item, err, _reason, lookup_diagnostics = target.resolve(destination)
    end

    if not item then
        return false, err or "no session for current working directory"
    end

    -- A live current session is already loaded. Do not require its persisted
    -- snapshot merely to make an idempotent load succeed.
    local current = state.get_current_session()
    if current and current.id == item.id then
        return true, nil, current, lookup_diagnostics or {}
    end

    local valid, validation_err = M.validate(item)
    if not valid then
        return false, validation_err
    end

    local ready, pre_err = observer.before("load", item, callbacks)
    if not ready then
        return false, pre_err
    end

    item, err = catalog.resolve(item)
    if not item then
        return false, err
    end

    valid, validation_err = M.validate(item)
    if not valid then
        return false, validation_err
    end

    local saved, save_err, outgoing_item, diagnostics = save.outgoing(callbacks)
    if not saved then
        return false, save_err
    end
    vim.list_extend(diagnostics, lookup_diagnostics or {})

    -- Saving the outgoing session can trigger observers that modify storage.
    item, err = catalog.resolve(item)
    if not item then
        return false, err
    end

    valid, validation_err = M.validate(item)
    if not valid then
        return false, validation_err
    end

    local changed, change_err, restore_diagnostics = rollback.change(function()
        local view = state.get_view(item.id)
        if editor.load ~= editor._legacy_load then
            return editor.load(item, view)
        end
        if view then
            return editor.restore(view)
        end

        editor.empty(item.metadata.cwd)
        local snapshot_path = assert(storage.get_session_path(item.id))
        local snapshot_content, snapshot_err = storage.read_session(item.id)
        if not snapshot_content then
            return false, snapshot_err
        end
        local sourced, source_err = editor.source_snapshot(snapshot_path, snapshot_content)
        if sourced == false then
            return false, source_err
        end
        return {}
    end)
    if not changed then
        return false, change_err
    end

    vim.list_extend(diagnostics, restore_diagnostics or {})
    item = save.touch(item, diagnostics)
    commit.activate(item, outgoing_item)

    return observer.finish("load", item, callbacks, diagnostics)
end

function M.validate(item)
    if vim.fn.isdirectory(item.metadata.cwd) == 0 then
        return false, "directory does not exist: " .. item.metadata.cwd
    end
    return storage.validate_snapshot(item.id)
end

function M.last(options, context)
    local previous = state.get_prev_session()
    if previous then
        return M.run(previous, options, context)
    end

    local sessions, err, catalog_diagnostics = catalog.list()
    if err then
        return false, err
    end

    local current_session = state.get_current_session()
    local selected
    local function preferred(candidate, existing)
        if candidate.metadata.last_used_at ~= existing.metadata.last_used_at then
            return candidate.metadata.last_used_at > existing.metadata.last_used_at
        end

        local candidate_name = candidate.metadata.name:lower()
        local existing_name = existing.metadata.name:lower()
        if candidate_name ~= existing_name then
            return candidate_name < existing_name
        end

        return candidate.id < existing.id
    end

    for _, item in ipairs(sessions) do
        if not current_session or item.id ~= current_session.id then
            if not selected or preferred(item, selected) then
                selected = item
            end
        end
    end

    if not selected then
        return false, "no previous session"
    end

    local ok, load_err, loaded, load_diagnostics = M.run(selected, options, context)
    if not ok then
        return false, load_err
    end

    local diagnostics = vim.deepcopy(catalog_diagnostics or {})
    vim.list_extend(diagnostics, load_diagnostics or {})
    return true, nil, loaded, diagnostics
end

return M
