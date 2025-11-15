local M = {}

---@return nil
function M.open_list()
    if not pcall(require, "telescope") then
        vim.notify("You need to install telescope.nvim for this command", vim.log.levels.ERROR)
        return
    end
    require("sessions.telescope.custom_actions").open_sessions_list()
end

return M
