local editor = require("sess.editor")

local M = {}

-- Rollback is deliberately limited to reversible editor state. Sourced
-- Vimscript, user callbacks, deleted buffers, and stopped jobs are external.
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

return M
