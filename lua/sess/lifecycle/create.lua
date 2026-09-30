local catalog = require("sess.session")
local editor = require("sess.editor")
local observer = require("sess.lifecycle.observer")
local save = require("sess.lifecycle.save")
local rollback = require("sess.lifecycle.editor_rollback")
local commit = require("sess.lifecycle.commit")

local M = {}

function M.run(cwd, options, context)
    if cwd ~= nil and (type(cwd) ~= "string" or vim.trim(cwd) == "") then
        return false, "working directory must be a non-empty string"
    end

    if options ~= nil and type(options) ~= "table" then
        return false, "create options must be a table"
    end

    options = options or {}
    for key in pairs(options) do
        if key ~= "name" and key ~= "id" and key ~= "hooks" then
            return false, "unknown create option: " .. tostring(key)
        end
    end

    local callbacks = context.hooks

    local request = { cwd = cwd or vim.fn.getcwd(), name = options.name, id = options.id }
    local item, err = catalog.prepare_create(request)
    if not item then
        return false, err
    end

    local ready, pre_err = observer.before("create", item, callbacks)
    if not ready then
        return false, pre_err
    end

    -- Hooks and outgoing observers may change uniqueness or the target path.
    request.cwd, request.id = item.metadata.cwd, item.id
    item, err = catalog.prepare_create(request)
    if not item then
        return false, err
    end

    local saved, save_err, current, diagnostics = save.outgoing(callbacks)
    if not saved then
        return false, save_err
    end

    item, err = catalog.prepare_create(request)
    if not item then
        return false, err
    end

    local created
    local changed, change_err = rollback.change(function()
        editor.empty(item.metadata.cwd)

        local create_err
        created, create_err = catalog.create(request)
        if not created then
            error(create_err)
        end

        local ok, snapshot_err = save.snapshot(created)
        if not ok then
            error(snapshot_err)
        end
    end)
    if not changed then
        if created then
            local removed, remove_err = catalog.delete(created.id, true)
            if not removed then
                change_err = change_err .. "; cleanup failed: " .. tostring(remove_err)
            end
        end

        return false, change_err
    end

    commit.activate(created, current)
    return observer.finish("create", created, callbacks, diagnostics)
end

return M
