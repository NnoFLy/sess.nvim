local M = {}

-- Reserved for sess.nvim; keep the internal suffix to avoid common user groups.
local GROUP = "SessNvimInternal"

local function report(ok, err, _, diagnostics)
    local log = require("sess.log")
    if not ok then
        log.error(err or "Automatic session operation failed")
    end
    -- Partial failures can carry useful diagnostics from committed operations.
    log.diagnostics(diagnostics)
end

---@param opts Sess.Opts
function M.setup(opts)
    local group = vim.api.nvim_create_augroup(GROUP, { clear = true })

    require("sess.startup").setup(group, opts.smart_auto_load, function(mode)
        report(require("sess.api.resume").startup(mode))
    end)

    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            report(require("sess.api.resume").exit(opts))
        end,
    })
end

return M
