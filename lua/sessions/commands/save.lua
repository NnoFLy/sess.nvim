local M = {}

---@return boolean
function M.save_session()
    local utils = require("sessions.utils")
    local cwd = utils.from_path(vim.fn.getcwd())
    local file = utils.make_file_name(cwd .. ".vim")

    local cmd = "mksession! " .. file
    local ok, _ = pcall(function() vim.cmd(cmd) end)
    if not ok then
        return false
    end
    return true
end

return M
