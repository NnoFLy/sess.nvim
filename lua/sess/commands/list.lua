---@param opts table | nil
---@return nil
return function(opts)
    local log = require("sess.log")
    local ok, _ = pcall(require, "telescope")
    if not ok then
        log.error("You need to install telescope.nvim for this command")
        return
    end

    local sess = require("telescope._extensions.sess.pickers")
    sess(opts)
end
