---@param opts table | nil
---@return nil
return function(opts)
    local logger = require("sess.logger")
    local ok, _ = pcall(require, "telescope")
    if not ok then
        logger.error("You need to install telescope.nvim for this command")
        return
    end

    local sess = require("telescope._extensions.sess.pickers")
    sess(opts)
end
