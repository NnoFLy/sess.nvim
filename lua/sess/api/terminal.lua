local opts = require("sess.api.opts")
local scope = require("sess.lifecycle.operation_scope")
local terminal = require("sess.lifecycle.terminal")
local M = {}

local function invoke(operation, validate)
    return function(...)
        if not opts.is_setup() then
            return false, "sess.nvim is not initialized; call setup() first"
        end
        if select("#", ...) > 1 then
            return false,
                "terminal operation accepts at most one argument; options are not supported"
        end
        local valid, err = validate(...)
        if not valid then
            return false, err
        end
        return scope.wrap(operation, true)(...)
    end
end

-- Both operations return true, nil, {id, execution, bufnr, job_id}, diagnostics
-- or false, error. Attachment failure never undoes a committed execution.
M.launch = invoke(terminal.launch, function(command)
    if command ~= nil and (type(command) ~= "string" or command:find("%z") or #command > 32768) then
        return false, "terminal command must be a NUL-free string within 32768 bytes"
    end
    return true
end)

M.attach = invoke(terminal.attach, function(id)
    if not require("sess.terminal.storage").valid_id(id) then
        return false, "invalid terminal execution id"
    end
    return true
end)

-- Focus returns {id, execution, bufnr, job_id?}; completed output is a
-- read-only capture buffer without a job. attach() always opens a tmux client.
M.focus = invoke(function(id)
    return terminal.focus(id, { hooks = opts.get().hooks })
end, function(id)
    if not require("sess.terminal.storage").valid_id(id) then
        return false, "invalid terminal execution id"
    end
    return true
end)

-- true, nil, entries, diagnostics; false, error, retained_entries, diagnostics.
M.list = function(...)
    if not opts.is_setup() then
        return false, "sess.nvim is not initialized; call setup() first", {}, {}
    end
    if select("#", ...) > 0 then
        return false, "terminal.list() takes no arguments", {}, {}
    end
    return scope.wrap(terminal.list, false)()
end

return M
