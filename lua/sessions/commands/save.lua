local M = {}

---@return boolean
function M.save_session()
    local convert = require("sessions.convert")
    local cwd = convert.from_path(vim.fn.getcwd())
    local file = convert.make_file_name(cwd .. ".vim")

    local cmd = "mksession! " .. file
    local ok, _ = pcall(function() vim.cmd(cmd) end)
    if not ok then
        return false
    end
    return true
end

return M
