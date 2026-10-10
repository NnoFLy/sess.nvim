local M = {}

local function row_value(row)
    return row and (row.value or row)
end

function M.key(value)
    if not value then
        return nil
    end
    local id = value.id or value.session_id
    if id then
        return {
            id = id,
            kind = value.kind,
            agent_id = value.agent_id,
        }
    end
    if value.directory and value.path then
        return { directory = true, path = value.path }
    end
    return nil
end

local function same_key(left, right)
    return left
        and right
        and left.id == right.id
        and left.kind == right.kind
        and left.agent_id == right.agent_id
        and left.directory == right.directory
        and left.path == right.path
end

local function select_manager_entry(picker, index)
    local row = index
    if type(picker.get_row) == "function" then
        local ok, result = pcall(picker.get_row, picker, index)
        if ok then
            row = result
        end
    end
    pcall(picker.set_selection, picker, row)
    return true
end

local function restore_from_manager(picker, key, opts)
    local manager = picker.manager
    if
        type(manager) ~= "table"
        or type(manager.num_results) ~= "function"
        or type(manager.get_entry) ~= "function"
    then
        return nil
    end

    local count = manager:num_results()
    local function find(match_parent)
        for index = 1, count do
            local ok, entry = pcall(manager.get_entry, manager, index)
            local value = ok and row_value(entry) or nil
            if same_key(M.key(value), key) then
                return select_manager_entry(picker, index)
            end
            if match_parent and value and value.session_id == key.id and value.kind == "session" then
                return select_manager_entry(picker, index)
            end
        end
        return false
    end

    if find(false) or (opts and opts.parent and find(true)) then
        return true
    end

    -- A successful mutation can remove the selected row. Let Telescope select
    -- the first remaining row rather than retaining a stale entry.
    if count > 0 then
        local row = 0
        if type(picker.get_reset_row) == "function" then
            local ok, result = pcall(picker.get_reset_row, picker)
            if ok then
                row = result
            end
        end
        pcall(picker.set_selection, picker, row)
        return true
    end
    return false
end

function M.current_key(picker)
    if not picker or type(picker.get_selection) ~= "function" then
        return nil
    end
    local ok, selected = pcall(picker.get_selection, picker)
    return ok and M.key(row_value(selected)) or nil
end

function M.restore(picker, finder, key, opts)
    if type(picker.set_selection) ~= "function" or not key then
        return false
    end

    -- Finder results are not necessarily in display order. Once Telescope has
    -- completed the refresh, restore by manager position rather than by the
    -- raw finder index, otherwise selection can jump to a neighbouring row.
    local managed = restore_from_manager(picker, key, opts)
    if managed ~= nil then
        return managed
    end

    local rows = finder and finder.results or {}
    for index, row in ipairs(rows) do
        if same_key(M.key(row_value(row)), key) then
            pcall(picker.set_selection, picker, index)
            return true
        end
    end

    if opts and opts.parent then
        for index, row in ipairs(rows) do
            local value = row_value(row)
            if value and value.session_id == key.id and value.kind == "session" then
                pcall(picker.set_selection, picker, index)
                return true
            end
        end
    end

    if #rows > 0 then
        pcall(picker.set_selection, picker, 1)
        return true
    end
    return false
end

function M.attach(picker)
    if not picker or picker._sess_selection_restore_attached then
        return picker and picker._sess_selection_restore_attached == true
    end
    if type(picker.register_completion_callback) ~= "function" then
        return false
    end

    local ok = pcall(function()
        picker:register_completion_callback(function()
            M.restore_pending(picker)
        end)
    end)
    if ok then
        picker._sess_selection_restore_attached = true
    end
    return ok
end

function M.is_attached(picker)
    return picker and picker._sess_selection_restore_attached == true
end

function M.queue(picker, finder, key, opts)
    if not picker or not key then
        return
    end
    picker._sess_pending_selection_restore = {
        finder = finder,
        key = key,
        opts = opts,
    }
end

function M.restore_pending(picker)
    local pending = picker and picker._sess_pending_selection_restore
    if not pending then
        return false
    end
    picker._sess_pending_selection_restore = nil
    return M.restore(picker, picker.finder or pending.finder, pending.key, pending.opts)
end

function M.cancel(picker)
    if picker then
        picker._sess_pending_selection_restore = nil
    end
end

return M
