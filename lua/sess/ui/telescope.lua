local log = require("sess.log")

local M = {}

---@param opts table?
---@return boolean
function M.list(opts)
    local ok = pcall(require, "telescope")
    if not ok then
        log.error("You need to install telescope.nvim for this command")
        return false
    end

    require("telescope._extensions.sess.pickers")(opts)
    return true
end

return M
