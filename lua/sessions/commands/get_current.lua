local M = {}

---@param session_path string
---@return string | nil
M.get_session_name = function(session_path)
    local consts = require("sessions.consts")
    local utils = require("sessions.utils")

    local command = "find " ..
        consts.path .. " -type f -name '" .. consts.marker .. "*" .. utils.from_path(session_path) .. ".vim'"
    local res = vim.fn.system(command)
    if not res or res == "" then
        return nil
    end
    local result = utils.to_path(res)
    local start_pos = result:find(consts.marker .. "%(")
    local end_pos = result:find("%)/", start_pos)
    if start_pos == nil or end_pos == nil then
        return nil
    end
    local name = result:sub(start_pos + #consts.marker + 1, end_pos - 1)
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
