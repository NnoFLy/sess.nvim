local catalog = require("sess.session")
local editor = require("sess.editor")
local state = require("sess.state")
local opts = require("sess.api.opts")
local unload = require("sess.unload")

local M = {}

local busy = false

local function resolve(target)
    if target == nil then
        target = state.get_current_session()
        if not target then
            return nil, "no current session"
        end
    end

    return catalog.resolve(target)
end

local function hooks(overrides, extra_options)
    if overrides == nil then
        return opts.get().hooks
    end

    if type(overrides) ~= "table" then
        return nil, "options must be a table"
    end

    for key in pairs(overrides) do
        if key ~= "hooks" and not (extra_options and extra_options[key]) then
            return nil, "unknown operation option: " .. tostring(key)
        end
    end

    if overrides.hooks ~= nil then
        local valid, err = opts.validate_hooks(overrides.hooks)
        if not valid then
            return nil, err
        end
    end

    return vim.tbl_extend("force", opts.get().hooks, overrides.hooks or {})
end

local function before(operation, item, callbacks)
    if not callbacks.before_transition then
        return true
    end

    local ok, err = pcall(callbacks.before_transition, {
        operation = operation,
        session = vim.deepcopy(item),
        current = state.get_current_session(),
    })

    return ok, not ok and ("before_transition failed: " .. tostring(err)) or nil
end

local events = {
    create = "SessCreated",
    load = "SessLoaded",
    save = "SessSaved",
    unload = "SessUnloaded",
    delete = "SessDeleted",
    rename = "SessRenamed",
    pin = "SessPinned",
}

-- State is committed before observers run. Their failures are diagnostics, not
-- failed operations. The guard remains held through both hooks and User events.
local function finish(operation, item, callbacks, diagnostics)
    diagnostics = diagnostics or {}

    local payload = {
        operation = operation,
        session = vim.deepcopy(item),
        current = state.get_current_session(),
    }

    if callbacks.after_operation then
        local ok, err = pcall(callbacks.after_operation, vim.deepcopy(payload))
        if not ok then
            table.insert(diagnostics, "after_operation failed: " .. tostring(err))
        end
    end

    -- Neovim reports Lua autocmd errors itself rather than always throwing them
    -- through nvim_exec_autocmds. Preserve the caller's errmsg and collect both.
    local previous_error = vim.v.errmsg
    vim.v.errmsg = ""

    local ok, err = pcall(
        vim.api.nvim_exec_autocmds,
        "User",
        { pattern = events[operation], data = payload, modeline = false }
    )

    local subscriber_error = not ok and tostring(err) or vim.v.errmsg
    vim.v.errmsg = previous_error

    if subscriber_error ~= "" then
        table.insert(diagnostics, events[operation] .. " subscriber failed: " .. subscriber_error)
    end

    return true, nil, item, diagnostics
end

local function touch(item, diagnostics)
    local called, updated, err = pcall(catalog.touch, item.id)
    if not called then
        err, updated = updated, nil
    end

    if err then
        table.insert(diagnostics, "metadata update failed: " .. tostring(err))
    end

    return updated or item
end

local function save_current(callbacks)
    local item, err = resolve()
    if not item then
        return false, err
    end

    local view = editor.capture()
    local ok, save_err = editor.snapshot(item)
    if not ok then
        return false, save_err
    end

    view.this_session = vim.v.this_session
    state.set_view(item.id, view)

    local diagnostics = {}
    item = touch(item, diagnostics)
    state.replace(item)

    return finish("save", item, callbacks, diagnostics)
end

-- Recover the reversible editor state if any editor action or filesystem step
-- throws. This does not undo arbitrary sourced Vimscript or user autocommands.
local function change(action)
    local original = editor.capture()
    local ok, err = editor.protected(action)
    if not ok then
        local restored, restore_err = editor.protected(function()
            editor.restore(original, true)
        end)

        return false,
            tostring(err) .. (restored and "" or ("; rollback failed: " .. tostring(restore_err)))
    end

    return true
end

local function outgoing(callbacks)
    if not state.get_current_session() then
        return true, nil, nil, {}
    end

    local ok, err, item, diagnostics = save_current(callbacks)
    if not ok then
        return false, "failed to save outgoing session: " .. tostring(err)
    end

    return true, nil, item, diagnostics
end

function M.create(cwd, options)
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

    local callbacks, hook_err = hooks({ hooks = options.hooks })
    if not callbacks then
        return false, hook_err
    end

    local request = { cwd = cwd or vim.fn.getcwd(), name = options.name, id = options.id }
    local item, err = catalog.prepare_create(request)
    if not item then
        return false, err
    end

    local ready, pre_err = before("create", item, callbacks)
    if not ready then
        return false, pre_err
    end

    -- Hooks may remove directories or introduce conflicts. Revalidate before
    -- saving the outgoing session or changing its visibility.
    request.cwd, request.id = item.metadata.cwd, item.id
    item, err = catalog.prepare_create(request)
    if not item then
        return false, err
    end

    local saved, save_err, current, diagnostics = outgoing(callbacks)
    if not saved then
        return false, save_err
    end

    item, err = catalog.prepare_create(request)
    if not item then
        return false, err
    end

    local created
    local changed, change_err = change(function()
        editor.empty(item.metadata.cwd)

        local create_err
        created, create_err = catalog.create(request)
        if not created then
            error(create_err)
        end

        local ok, snapshot_err = editor.snapshot(created)
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

    if current then
        state.set_prev_session(current)
    end

    state.set_current_session(created)
    state.add_active_session(created)

    return finish("create", created, callbacks, diagnostics)
end

function M.load(target, options)
    local callbacks, hook_err = hooks(options)
    if not callbacks then
        return false, hook_err
    end

    local item, err
    if target == nil then
        item, err = catalog.get_by_path(vim.fn.getcwd())
    else
        item, err = resolve(target)
    end

    if not item then
        return false, err or "no session for current working directory"
    end

    local valid, validation_err = editor.validate(item)
    if not valid then
        return false, validation_err
    end

    local current = state.get_current_session()
    if current and current.id == item.id then
        return true, nil, current, {}
    end

    local ready, pre_err = before("load", item, callbacks)
    if not ready then
        return false, pre_err
    end

    item, err = catalog.resolve(item)
    if not item then
        return false, err
    end

    valid, validation_err = editor.validate(item)
    if not valid then
        return false, validation_err
    end

    local saved, save_err, outgoing_item, diagnostics = outgoing(callbacks)
    if not saved then
        return false, save_err
    end

    -- Outgoing save observers can invalidate the target as well.
    item, err = catalog.resolve(item)
    if not item then
        return false, err
    end

    valid, validation_err = editor.validate(item)
    if not valid then
        return false, validation_err
    end

    local changed, change_err = change(function()
        editor.load(item, state.get_view(item.id))
    end)
    if not changed then
        return false, change_err
    end

    item = touch(item, diagnostics)
    if outgoing_item then
        state.set_prev_session(outgoing_item)
    end

    state.set_current_session(item)
    state.add_active_session(item)

    return finish("load", item, callbacks, diagnostics)
end

function M.save(...)
    if select("#", ...) > 0 then
        return false, "save() takes no arguments and saves only the current session"
    end

    return save_current(opts.get().hooks)
end

---@param target string|Sess.Session|Sess.UnloadOpts?
---@param options Sess.UnloadOpts?
function M.unload(target, options)
    -- Preserve unload({ hooks = ... }) for callers of the current-only API.
    if
        type(target) == "table"
        and target.id == nil
        and target.metadata == nil
        and options == nil
    then
        options, target = target, nil
    end

    local callbacks, hook_err = hooks(options, { confirm = true })
    if not callbacks then
        return false, hook_err
    end
    if options and options.confirm ~= nil and type(options.confirm) ~= "function" then
        return false, "unload confirm must be a function"
    end

    local item, err = resolve(target)
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

    local ready, pre_err = before("unload", item, callbacks)
    if not ready then
        return false, pre_err
    end

    item, err = resolve(item)
    if not item then
        return false, err
    end

    local plan, plan_err = unload.prepare(item, options and options.confirm)
    if not plan then
        return false, plan_err
    end

    item, err = resolve(item)
    if not item then
        return false, err
    end

    local saved, save_err = unload.save_buffers(plan)
    if not saved then
        return false, save_err
    end

    -- Only the current session can be snapshotted from the editor. Hidden
    -- sessions retain the snapshot written when switching away from them.
    local diagnostics = {}
    if is_current then
        saved, save_err, item, diagnostics = outgoing(callbacks)
        if not saved then
            return false, save_err
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

    -- Restore remaining editor state on failure, but deleted buffers and
    -- stopped jobs are irreversible. Runtime records commit only on success.
    local changed, change_err
    if is_current then
        changed, change_err = change(close)
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

    return finish("unload", item, callbacks, diagnostics)
end

function M.delete(target, options)
    local callbacks, hook_err = hooks(options)
    if not callbacks then
        return false, hook_err
    end

    local item, err = resolve(target)
    if not item then
        return false, err
    end

    local current = state.get_current_session()
    local is_current = current and current.id == item.id
    if is_current then
        local ready, pre_err = before("delete", item, callbacks)
        if not ready then
            return false, pre_err
        end

        item, err = resolve(item)
        if not item then
            return false, err
        end
    end

    local changed, change_err
    if is_current then
        changed, change_err = change(function()
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

    local diagnostics = {}
    if is_current then
        local _, _, _, unload_diagnostics = finish("unload", item, callbacks)
        diagnostics = unload_diagnostics
    end

    return finish("delete", item, callbacks, diagnostics)
end

function M.rename(target, name)
    if type(name) ~= "string" or vim.trim(name) == "" then
        return false, "session name cannot be empty"
    end

    local item, err = resolve(target)
    if not item then
        return false, err
    end

    local renamed, rename_err = catalog.rename(item.id, name)
    if not renamed then
        return false, rename_err
    end

    state.replace(renamed)

    return finish("rename", renamed, opts.get().hooks)
end

function M.toggle_pin(target)
    local item, err = resolve(target)
    if not item then
        return false, err
    end

    local updated, pin_err = catalog.toggle_pinned(item.id)
    if not updated then
        return false, pin_err
    end

    state.replace(updated)

    return finish("pin", updated, opts.get().hooks)
end

function M.resolve(target)
    local item, err, reason = resolve(target)

    return item ~= nil, err, item, reason
end

function M.list()
    local items, err, diagnostics = catalog.list()

    return err == nil, err, items, diagnostics
end

for name, query in pairs({
    get_by_id = catalog.get,
    get_by_name = catalog.get_by_name,
    get_by_path = catalog.get_by_path,
}) do
    M[name] = function(value)
        local item, err = query(value)

        return err == nil, err, item
    end
end

local mutations = {
    create = true,
    load = true,
    save = true,
    unload = true,
    delete = true,
    rename = true,
    toggle_pin = true,
}

for name, operation in pairs(M) do
    M[name] = function(...)
        if not opts.is_setup() then
            return false, "sess.nvim is not initialized; call setup() first"
        end

        if mutations[name] and busy then
            return false, "session transition already in progress"
        end

        if mutations[name] then
            busy = true
        end

        local args, count = { ... }, select("#", ...)
        local called, ok, err, item, diagnostics = xpcall(function()
            return operation(unpack(args, 1, count))
        end, debug.traceback)
        if mutations[name] then
            busy = false
        end

        if not called then
            return false, tostring(ok)
        end

        return ok, err, item, diagnostics
    end
end

return M
