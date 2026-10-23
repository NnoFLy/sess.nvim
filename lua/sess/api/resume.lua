local opts = require("sess.api.opts")
local scope = require("sess.lifecycle.operation_scope")
local resume = require("sess.lifecycle.resume")

local M = {}

-- Startup eligibility belongs to the event/editor adapter. These entry points
-- orchestrate ordinary lifecycle operations under a single observer guard.
---@param mode "none"|"current"|"all"?
---@return boolean, string?, Sess.ResumeResult?, string[]?
function M.startup(mode)
    if not opts.is_setup() then
        return false, "sess.nvim is not initialized; call setup() first"
    end
    local configured = opts.get()
    if mode == nil then
        mode = configured.smart_auto_load
    end
    return scope.wrap(resume.startup, true)(mode, { hooks = configured.hooks })
end

---@param options Sess.Opts? Captured setup policy for the managed exit adapter.
---@return boolean, string?, Sess.ResumeRecord?, string[]?
function M.exit(options)
    if not opts.is_setup() then
        return false, "sess.nvim is not initialized; call setup() first"
    end
    local configured = opts.get()
    return scope.wrap(resume.exit, true)(options or configured, { hooks = configured.hooks })
end

return M
