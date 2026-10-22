local catalog = require("sess.session")
local state = require("sess.state")
local storage = require("sess.storage")
local load = require("sess.lifecycle.load")
local create = require("sess.lifecycle.create")
local save = require("sess.lifecycle.save")

local M = {}

local function result()
    return { restored_ids = {}, current_id = state.get_current_session_id() }
end

local function current(context)
    local item, err, diagnostics = catalog.get_by_path(vim.fn.getcwd())
    diagnostics = diagnostics or {}
    if err then
        return false, err, result(), diagnostics
    end
    -- A skipped corrupt catalog entry is not evidence of an unmatched cwd.
    if not item and #diagnostics > 0 then
        return false,
            "cannot create startup session: catalog contains unusable records",
            result(),
            diagnostics
    end
    local ok, operation_err, loaded, warnings
    if item then
        ok, operation_err, loaded, warnings = load.run(item.id, nil, context)
    else
        ok, operation_err, loaded, warnings = create.run(vim.fn.getcwd(), nil, context)
    end
    vim.list_extend(diagnostics, warnings or {})
    local resumed = result()
    if ok then
        resumed.restored_ids = { loaded.id }
    end
    return ok, operation_err, resumed, diagnostics
end

local function all(context)
    local resumed, diagnostics = result(), {}
    local ok, err, record = storage.read_resume()
    if not ok or not record then
        return ok, err, resumed, diagnostics
    end

    local survivors, available = {}, {}
    for _, id in ipairs(record.active_ids) do
        local item, lookup_err = catalog.get(id)
        local valid, validation_err
        if item then
            valid, validation_err = load.validate(item)
            if valid then
                local status
                status, validation_err = storage.inspect_snapshot(id)
                valid = status == "available"
            end
        end
        if item and valid then
            survivors[#survivors + 1] = id
            available[id] = true
        else
            diagnostics[#diagnostics + 1] = "cannot resume "
                .. id
                .. ": "
                .. tostring(lookup_err or validation_err or "session not found")
        end
    end
    local selected = available[record.current_id] and record.current_id or survivors[1]
    if not selected then
        return true, nil, resumed, diagnostics
    end
    local ordered = {}
    for _, id in ipairs(survivors) do
        if id ~= selected then
            ordered[#ordered + 1] = id
        end
    end
    ordered[#ordered + 1] = selected

    for _, id in ipairs(ordered) do
        local loaded, load_err, _, warnings = load.run(id, nil, context)
        vim.list_extend(diagnostics, warnings or {})
        -- Preserve recorded order even on partial progress. Ordinary loads may
        -- select the current session last; observers still see normal commits.
        local active = {}
        for _, session in ipairs(state.get_active_sessions()) do
            active[session.id] = true
        end
        local active_order = {}
        for _, recorded in ipairs(record.active_ids) do
            if active[recorded] then
                active_order[#active_order + 1] = recorded
            end
        end
        local reordered, order_err = state.set_active_order(active_order)
        resumed.restored_ids = active_order
        resumed.current_id = state.get_current_session_id()
        if not loaded then
            resumed.failed_id = id
            return false, load_err, resumed, diagnostics
        end
        if not reordered then
            return false, order_err, resumed, diagnostics
        end
    end
    return true, nil, resumed, diagnostics
end

function M.startup(mode, context)
    if mode == "none" then
        return true, nil, result(), {}
    elseif mode == "current" then
        return current(context)
    elseif mode == "all" then
        return all(context)
    end
    return false, "smart_auto_load must be none, current or all", result(), {}
end

function M.exit(options, context)
    local diagnostics = {}
    if not state.has_managed_sessions() then
        return true, nil, nil, diagnostics
    end
    if
        options.auto_save
        and state.get_current_session()
        and not vim.tbl_contains(options.exclude_filetypes or {}, vim.bo.filetype)
    then
        local ok, err, _, warnings = save.current(context.hooks)
        vim.list_extend(diagnostics, warnings or {})
        if not ok then
            return false, err, nil, diagnostics
        end
    end
    local record = state.get_resume_state()
    local ok, err = storage.write_resume(record)
    return ok, err, record, diagnostics
end

return M
