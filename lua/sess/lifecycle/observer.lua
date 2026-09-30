local state = require("sess.state")

local M = {}

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
    mark = "SessMarked",
    unmark = "SessUnmarked",
}

-- State is committed before observers run. Their failures are diagnostics, not
-- failed operations. The transaction guard remains held through hooks/events.
function M.finish(operation, item, callbacks, diagnostics, details)
    diagnostics = diagnostics or {}

    local payload = {
        operation = operation,
        session = vim.deepcopy(item),
        current = state.get_current_session(),
    }

    for key, value in pairs(details or {}) do
        payload[key] = vim.deepcopy(value)
    end

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
