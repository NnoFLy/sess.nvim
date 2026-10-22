local backend = require("sess.terminal.backend")
local view = require("sess.terminal.view")
local catalog = require("sess.session")
local state = require("sess.state")
local M = {}
local inventory_root, last_inventory = nil, {}

local function attach(execution, diagnostics, focus, execution_state)
    local called, item, err = pcall(focus and view.focus or view.open, execution, execution_state)
    if not called then
        err, item = item, nil
    end
    if not item then
        return false,
            "terminal execution " .. execution.id .. " survives; attachment failed: " .. tostring(
                err
            )
    end
    return true, nil, item, diagnostics or {}
end

function M.launch(command)
    local owner = state.get_current_session()
    local diagnostics = {}
    if owner then
        local err, reason
        owner, err, reason, diagnostics = catalog.resolve(owner)
        if not owner then
            return false, err
        end
    end
    local execution, err = backend.create({
        owner_id = owner and owner.id or nil,
        cwd = vim.fn.getcwd(),
        command = command,
        shell = vim.o.shell,
    })
    if not execution then
        return false, err
    end
    return attach(execution, diagnostics)
end

function M.list()
    local root = require("sess.storage").root()
    if inventory_root ~= root then
        inventory_root, last_inventory = root, {}
    end
    local called, entries, err, diagnostics, missing = pcall(backend.list)
    if not called then
        err, entries, diagnostics = tostring(entries), {}, { tostring(entries) }
    end
    if missing and #last_inventory > 0 then
        err = "terminal registry disappeared; previous inventory retained"
        diagnostics[#diagnostics + 1] = err
    end
    if err then
        local seen = {}
        for _, entry in ipairs(entries) do
            seen[entry.id] = true
        end
        for _, previous in ipairs(last_inventory) do
            if not seen[previous.id] then
                local retained = vim.deepcopy(previous)
                retained.execution_state, retained.available = "unknown", false
                entries[#entries + 1] = retained
            end
        end
        table.sort(entries, function(a, b)
            return a.id < b.id
        end)
    end
    for _, entry in ipairs(entries) do
        if entry.owner_id then
            local owner, owner_err = catalog.get(entry.owner_id)
            if owner then
                entry.owner_name = owner.metadata.name
            else
                diagnostics[#diagnostics + 1] = "terminal "
                    .. entry.id
                    .. ": "
                    .. (owner_err or ("owner not found: " .. entry.owner_id))
            end
        end
    end
    last_inventory = vim.deepcopy(entries)
    return err == nil, err, entries, diagnostics
end

function M.attach(id)
    local execution, err = backend.get(id)
    if not execution then
        return false, err
    end
    return attach(execution)
end

function M.focus(id, context)
    local execution, err = backend.get(id)
    if not execution then
        return false, err
    end
    local diagnostics = {}
    if execution.owner_id then
        -- Resolve by full ID, never by a display label or name fallback.
        local owner, owner_err = catalog.get(execution.owner_id)
        if not owner then
            return false, owner_err or ("terminal owner not found: " .. execution.owner_id)
        end
        local loaded, load_err, _, load_diagnostics =
            require("sess.lifecycle.load").run(owner, nil, context)
        if not loaded then
            return false, load_err
        end
        vim.list_extend(diagnostics, load_diagnostics or {})
    end
    -- Hooks, snapshots and editor callbacks may have changed the backend while
    -- loading. Never attach a changed association after an owner transition.
    local checked, check_err, execution_state = backend.get(id)
    if not checked or not vim.deep_equal(checked, execution) then
        return false, check_err or "terminal association changed during focus"
    end
    return attach(checked, diagnostics, true, execution_state)
end

return M
