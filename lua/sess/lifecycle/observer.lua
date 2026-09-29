local opts = require("sess.api.opts")
local state = require("sess.state")

local M = {}

function M.hooks(overrides, extra_options)
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

function M.before(operation, item, callbacks)
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
    restore = "SessRestored",
}

-- State is committed before observers run. Their failures are diagnostics, not
-- failed operations. The transaction guard remains held through hooks/events.
function M.finish(operation, item, callbacks, diagnostics)
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

return M
