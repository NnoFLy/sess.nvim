local M = {}

---@param prompt_title string | nil
---@return nil
function M.open_list(prompt_title)
    local logger = require("sessions.logger")
    local opts = require("sessions").get_opts()

    prompt_title = prompt_title or opts.prompt_title

    if not pcall(require, "telescope") then
        logger.error("You need to install telescope.nvim for this command")
        return
    end
    require("sessions.telescope.custom_actions").open_sessions_list(prompt_title)
end

return M
