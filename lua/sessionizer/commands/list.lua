---@param opts table | nil
---@return nil
return function(opts)
    local logger = require("sessionizer.logger")
    local ok, _ = pcall(require, "telescope")
    if not ok then
        logger.error("You need to install telescope.nvim for this command")
        return
    end

    local sessionizer = require("telescope._extensions.sessionizer.pickers")
    sessionizer(opts)
end
