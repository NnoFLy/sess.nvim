local editor = require("sess.editor")
local opts = require("sess.api.opts")
local state = require("sess.state")

local M = {}
local busy = false

-- Only public entry points acquire the guard. Internal operations (such as an
-- outgoing save) share it, and observers run before it is released.
function M.wrap(operation, mutation)
    return function(...)
        if not opts.is_setup() then
            return false, "sess.nvim is not initialized; call setup() first"
        end

        if mutation and busy then
            return false, "session transition already in progress"
        end

        if mutation then
            busy = true
        end

        local args, count = { ... }, select("#", ...)
        local called, ok, err, item, diagnostics, extra = xpcall(function()
            return operation(unpack(args, 1, count))
        end, debug.traceback)
        if mutation then
            busy = false
        end

        if not called then
            return false, tostring(ok)
        end

        return ok, err, item, diagnostics, extra
    end
end

-- Recover reversible editor state on failure. Arbitrary sourced Vimscript,
-- user autocommands, deleted buffers and stopped jobs cannot be rolled back.
function M.change(action)
    local original = editor.capture()
    local ok, result = editor.protected(action)
    if not ok then
        local restored, restore_err = editor.protected(function()
            editor.restore(original, true)
        end)

        return false,
            tostring(result)
                .. (restored and "" or ("; rollback failed: " .. tostring(restore_err)))
    end

    return true, nil, result
end

-- Shared runtime commit for successful create/load transitions. Observers must
-- run only after this, never as part of the reversible editor action.
function M.activate(item, outgoing)
    if outgoing then
        state.set_prev_session(outgoing)
    end

    state.set_current_session(item)
    state.add_active_session(item)
end

return M
