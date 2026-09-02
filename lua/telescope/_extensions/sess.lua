local log = require("sess.log")

local ok, telescope = pcall(require, "telescope")
if not ok then
    log.error("You need to install telescope.nvim for this command")
    return
end

local config = require("telescope._extensions.sess.config")

return telescope.register_extension({
    setup = config.setup,
    exports = {
        sess = require("telescope._extensions.sess.pickers"),
    },
})
