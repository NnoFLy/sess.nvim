local M = {}

---@param session_path string
---@return string | nil
M.get_session_name = function(session_path)
    local opts = require("sessions").get_opts()
    local utils = require("sessions.utils")

    local result = vim.fn.system("find " .. opts.path .. " -type f -name '*)" .. utils.from_path(session_path) .. ".vim'")
    local start_pos = result:find(opts._marker .. "%(")
    local end_pos = result:find("%):", start_pos)
    if start_pos == nil or end_pos == nil then
        return nil
    end
    local name = result:sub(start_pos + 11, end_pos - 1)
    return utils.to_path(name)
end

---@return Session
M.get_current = function()
    local path = vim.fn.getcwd()
    return {
        path = path,
        name = M.get_session_name(path)
    }
end

return M
