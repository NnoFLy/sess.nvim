local M = {}

---@return boolean
function M.save_session()
    local session = require("sessions.session")
    local utils = require("sessions.utils")

    local s = session.new()
    local ok = session.save(s)
    if not ok then
        utils.notify("Failed to save session", vim.log.levels.ERROR)
        return false
    end
    return true
end

return M
