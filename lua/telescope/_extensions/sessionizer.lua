local logger = require("sessions.logger")

local ok, telescope = pcall(require, "telescope")
if not ok then
    logger.error("You need to install telescope.nvim for this command")
    return
end

local config = require("telescope._extensions.sessionizer.config")

return telescope.register_extension({
    setup = config.setup,
    exports = {
        sessionizer = require("telescope._extensions.sessionizer.pickers"),
    },
})
