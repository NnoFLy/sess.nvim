local M = {}

---@param opts table | nil
function M.open_telescope_sessionizer(opts)
    local logger = require("sessionizer.logger")
    local ok, _ = pcall(require, "telescope")
    if not ok then
        logger.error("You need to install telescope.nvim for this command")
        return
    end

    local sessionizer = require("telescope._extensions.sessionizer.pickers")
    sessionizer(opts)
end

return M
