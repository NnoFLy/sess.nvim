local session = require("sess.session")
local buffers = require("sess.buffers")
local state = require("sess.api.state")
local api_opts = require("sess.api.opts")

local M = {}

local function merge_opts(overrides)
    overrides = overrides or {}
    return {
        before_load = vim.tbl_deep_extend("force", api_opts.get().before_load, overrides.before_load or {}),
        after_load = vim.tbl_deep_extend("force", api_opts.get().after_load, overrides.after_load or {}),
        on_unload = vim.tbl_deep_extend("force", api_opts.get().on_unload, overrides.on_unload or {}),
    }
end

local function modified_buffers()
    local modified = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr)
            and vim.api.nvim_buf_get_name(bufnr) ~= ""
            and vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
            and vim.api.nvim_get_option_value("modified", { buf = bufnr })
        then
            table.insert(modified, vim.api.nvim_buf_get_name(bufnr))
        end
    end
    return modified
end

local function save_session(item)
    local ok, err = session.save(item.id)
    if not ok then
        return false, err
    end

    local updated, get_err = session.get(item.id)
    if not updated then
        return false, get_err or "failed to reload session after save"
    end

    state.replace(updated)
    return true, nil, updated
end

local function save_session_in_its_cwd(item)
    local previous = vim.fn.getcwd()
    local target_cwd = vim.fs.normalize(item.metadata.cwd)
    if previous == target_cwd then
        return save_session(item)
    end

    local changed, change_err = pcall(vim.fn.chdir, target_cwd)
    if not changed then
        return false, tostring(change_err)
    end

    local call_ok, save_ok, save_err, updated = pcall(save_session, item)
    local restored, restore_err = pcall(vim.fn.chdir, previous)
    if not restored then
        return false, "failed to restore working directory: " .. tostring(restore_err)
    end
    if not call_ok then
        return false, tostring(save_ok)
    end
    if not save_ok then
        return false, save_err
    end
    return true, nil, updated
end

---@param target Sess.Session | string | nil
---@return boolean, string?, Sess.Session?
function M.resolve(target)
    if target == nil then
        local current = state.current()
        if current then
            return true, nil, current
        end
        return false, "no current session"
    end

    if type(target) == "table" and target.id and target.metadata then
        local fresh, err = session.get(target.id)
        if not fresh then
            return false, err or ("session not found: " .. target.id)
        end
        return true, nil, fresh
    end

    if type(target) ~= "string" then
        return false, "invalid session target: " .. type(target)
    end

    target = vim.trim(target)
    if target == "" then
        return false, "session target cannot be empty"
    end

    local item, err = session.get(target)

    if err and not item then
        -- A malformed id should not prevent name/path fallback.
    end

    if item then
        return true, nil, item
    end

    item, err = session.get_by_name(target)
    if err then
        return false, err
    end
    if item then
        return true, nil, item
    end

    item, err = session.get_by_path(target)
    if err then
        return false, err
    end
    if item then
        return true, nil, item
    end

    return false, "session not found: " .. target
end

---@param cwd string?
---@param create_opts Sess.CreateOpts?
---@return boolean, string?, Sess.Session?
function M.create(cwd, create_opts)
    cwd = cwd or vim.fn.getcwd()
    cwd = vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p"))
    if create_opts ~= nil and type(create_opts) ~= "table" then
        return false, "create options must be a table"
    end
    create_opts = create_opts or {}

    if vim.fn.isdirectory(cwd) == 0 then
        return false, "directory does not exist: " .. cwd
    end

    local existing, lookup_err = session.get_by_path(cwd)
    if lookup_err then
        return false, lookup_err
    end
    if existing then
        return false, "session already exists for directory: " .. cwd
    end

    local previous_cwd = vim.fn.getcwd()
    local current = state.current()
    if current then
        local ok, err, updated = save_session(current)
        if not ok then
            return false, "failed to save current session: " .. tostring(err)
        end
        current = updated
    end

    local changed, change_err = pcall(vim.fn.chdir, cwd)
    if not changed then
        return false, tostring(change_err)
    end

    local hidden, hide_err = true, nil
    hidden, hide_err = buffers.hide_all_buffers()
    if not hidden then
        pcall(vim.fn.chdir, previous_cwd)
        return false, hide_err
    end

    local edited, edit_err = pcall(vim.cmd, "edit .")
    if not edited then
        pcall(vim.fn.chdir, previous_cwd)
        return false, tostring(edit_err)
    end

    local item, create_err = session.create({
        cwd = cwd,
        name = create_opts.name,
        id = create_opts.id,
    })
    if not item then
        pcall(vim.fn.chdir, previous_cwd)
        return false, create_err or "failed to create session"
    end

    if current then
        state.set_prev(current)
    end
    state.set_current(item)
    state.add_active(item)

    return true, nil, item
end

---@param target Sess.Session | Sess.SessionId | string | nil
---@return boolean, string?, Sess.Session?
function M.save(target)
    local item
    if target == nil then
        item = state.current()
        if not item then
            return false, "no current session"
        end
    elseif type(target) == "table" and target.id and target.metadata then
        local ok, err, resolved = M.resolve(target)
        if not ok then
            return false, err
        end
        item = resolved
    elseif type(target) == "string" then
        local resolved = session.get(target)
        if not resolved then
            resolved = session.get_by_name(target)
        end
        if not resolved then
            resolved = session.get_by_path(target)
        end
        if resolved then
            item = resolved
        else
            local cwd = vim.fs.normalize(vim.fn.fnamemodify(target, ":p"))
            if vim.fn.isdirectory(cwd) == 0 then
                return false, "directory does not exist: " .. cwd
            end

            local previous = vim.fn.getcwd()
            local changed, chdir_err = pcall(vim.fn.chdir, cwd)
            if not changed then
                return false, tostring(chdir_err)
            end

            local created, create_err = session.create({ cwd = cwd })
            local restored, restore_err = pcall(vim.fn.chdir, previous)
            if not restored then
                return false, "failed to restore working directory: " .. tostring(restore_err)
            end
            if not created then
                return false, create_err or "failed to create session"
            end
            return true, nil, created
        end
    else
        return false, "invalid save target: " .. type(target)
    end

    local ok, err, updated = save_session_in_its_cwd(item)
    if not ok then
        return false, err
    end
    return true, nil, updated
end

---@param target Sess.Session | string | nil
---@param opts Sess.MergedLoadOpts?
---@return boolean, string?, Sess.Session?, Sess.BeforeLoadOpts?, Sess.AfterLoadOpts?
function M.prepare(target, opts)
    local merged = merge_opts(opts)
    local item

    if target == nil then
        local lookup_err
        item, lookup_err = session.get_by_path(vim.fn.getcwd())
        if lookup_err then
            return false, lookup_err, nil, nil, nil
        end
        if not item then
            return false, "no session for current working directory: " .. vim.fn.getcwd(), nil, nil, nil
        end
    else
        local ok, err, resolved = M.resolve(target)
        if not ok then
            return false, err, nil, nil, nil
        end
        item = resolved
    end

    local modified = modified_buffers()
    if #modified > 0 then
        if not merged.before_load.auto_save_files then
            return false, "unsaved changes in buffers: " .. table.concat(modified, ", ")
                .. " (set before_load.auto_save_files to save them automatically)", nil, nil, nil
        end

        local ok, err = pcall(vim.cmd, "wall")
        if not ok then
            return false, tostring(err), nil, nil, nil
        end
    end

    local hook_ok, hook_err = pcall(merged.before_load.custom)
    if not hook_ok then
        return false, "before_load.custom failed: " .. tostring(hook_err), nil, nil, nil
    end

    return true, nil, item, merged.before_load, merged.after_load
end

---@param item Sess.Session
---@param opts Sess.MergedLoadOpts?
---@return boolean, string?, Sess.Session?, boolean
function M.commit(item, opts)
    local before_load = (opts or {}).before_load or {}
    local after_load = (opts or {}).after_load or {}
    local current = state.current()

    if current and current.id == item.id then
        return true, nil, current, true
    end

    if before_load.auto_hide_buffers then
        local ok, err = buffers.hide_all_buffers()
        if not ok then
            return false, err, nil, false
        end
    end

    local loaded, load_err = session.load_session(item.id)
    if not loaded then
        return false, load_err, nil, false
    end

    if current and current.id ~= item.id then
        state.set_prev(current)
    end

    local loaded_item = session.get(item.id) or item
    state.set_current(loaded_item)
    state.add_active(loaded_item)

    local hook_ok, hook_err = pcall(after_load.custom or function() end)
    if not hook_ok then
        return false, "after_load.custom failed: " .. tostring(hook_err), loaded_item, false
    end

    return true, nil, loaded_item, false
end

---@param target Sess.Session | string | nil
---@param opts Sess.MergedLoadOpts?
---@return boolean, string?, Sess.Session?, boolean
function M.load(target, opts)
    local ok, err, item, before_load, after_load = M.prepare(target, opts)
    if not ok then
        return false, err, nil, false
    end

    local current = state.current()
    if current and current.id == item.id then
        return true, nil, current, true
    end

    if current then
        local saved, save_err = save_session(current)
        if not saved then
            return false, "failed to save current session: " .. tostring(save_err), nil, false
        end
    end

    return M.commit(item, {
        before_load = before_load,
        after_load = after_load,
    })
end

---@param opts Sess.MergedUnloadOpts?
---@return boolean, string?
function M.unload(opts)
    local current = state.current()
    if not current then
        return false, "no current session"
    end

    local merged = merge_opts(opts)
    state.set_prev(current)
    state.set_current(nil)
    state.remove_active(current.id)

    local hook_ok, hook_err = pcall(merged.on_unload.custom)
    if not hook_ok then
        return false, "on_unload.custom failed: " .. tostring(hook_err)
    end

    return true
end

---@param target Sess.Session | string | nil
---@param opts Sess.MergedUnloadOpts?
---@return boolean, string?, Sess.Session?
function M.delete(target, opts)
    local ok, err, item = M.resolve(target)
    if not ok then
        return false, err
    end

    local deleted, delete_err = session.delete(item.id)
    if not deleted then
        return false, delete_err or "failed to delete session"
    end

    local current = state.current()
    if current and current.id == item.id then
        state.set_current(nil)
    end
    local previous = state.prev()
    if previous and previous.id == item.id then
        state.set_prev(nil)
    end
    state.remove_active(item.id)

    local merged = merge_opts(opts)
    local hook_ok, hook_err = pcall(merged.on_unload.custom)
    if not hook_ok then
        return false, "on_unload.custom failed: " .. tostring(hook_err), item
    end

    return true, nil, item
end

---@param target Sess.Session | string | nil
---@param name string
---@return boolean, string?, Sess.Session?
function M.rename(target, name)
    if type(name) ~= "string" or vim.trim(name) == "" then
        return false, "session name cannot be empty"
    end

    local ok, err, item = M.resolve(target)
    if not ok then
        return false, err
    end

    local renamed, rename_err = session.rename(item.id, name)
    if not renamed then
        return false, rename_err or "failed to rename session"
    end

    state.replace(renamed)
    return true, nil, renamed
end

---@param target Sess.Session | string | nil
---@return boolean, string?, Sess.Session?
function M.toggle_pin(target)
    local ok, err, item = M.resolve(target)
    if not ok then
        return false, err
    end

    local updated, pin_err = session.toggle_pinned(item.id)
    if not updated then
        return false, pin_err or "failed to toggle session pin"
    end

    state.replace(updated)
    return true, nil, updated
end

---@return boolean, string?, Sess.Session[]
function M.list()
    local sessions, err = session.list()
    if err then
        return false, err, sessions
    end
    return true, nil, sessions
end

---@param name string
---@return boolean, string?, Sess.Session?
function M.get_by_name(name)
    local item, err = session.get_by_name(name)
    if err then
        return false, err
    end
    return true, nil, item
end

---@param cwd string
---@return boolean, string?, Sess.Session?
function M.get_by_path(cwd)
    local item, err = session.get_by_path(cwd)
    if err then
        return false, err
    end
    return true, nil, item
end

---@param id Sess.SessionId
---@return boolean, string?, Sess.Session?
function M.get_by_id(id)
    local item, err = session.get(id)
    if err then
        return false, err
    end
    return true, nil, item
end

return M
