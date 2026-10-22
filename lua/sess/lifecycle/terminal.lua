local backend = require("sess.terminal.backend")
local view = require("sess.terminal.view")
local catalog = require("sess.session")
local state = require("sess.state")
local M = {}

local function attach(execution, diagnostics)
    local called, item, err = pcall(view.open, execution)
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

function M.attach(id)
    local execution, err = backend.get(id)
    if not execution then
        return false, err
    end
    return attach(execution)
end

return M
