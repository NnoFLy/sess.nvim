local M = {}
local busy = false

---@return boolean
function M.is_busy()
    return busy
end

-- Public entry points own setup validation; this module only scopes lifecycle
-- operations and keeps observers inside the same reentrancy boundary.
function M.wrap(operation, mutation)
    return function(...)
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

return M
