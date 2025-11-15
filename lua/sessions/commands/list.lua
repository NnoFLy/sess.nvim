local M = {}

---@param prompt_title string | nil
---@return nil
function M.open_list(prompt_title)
    if not pcall(require, "telescope") then
        vim.notify("You need to install telescope.nvim for this command", vim.log.levels.ERROR)
        return
    end
    local opts = require("sessions").get_opts()
    local title = prompt_title or opts.prompt_title
    require("sessions.telescope.custom_actions").open_sessions_list(title)
end

return M
