local M = {}

---@param name string
---@return Session | nil
function M.by_name(name)
    local consts = require("sessions.consts")
    local sessions = M.all(consts.path, consts.marker)
    for _, session in ipairs(sessions) do
        if session.name == name then
            return session
        end
    end
    return nil
end

---@param path string
---@param marker string
---@return Session[]
function M.all(path, marker)
    local convert = require("sessions.convert")
    local sessions = {}
    for k, _ in vim.fn.execute("!ls " .. path):gmatch("[A-Za-z_.%%:|0-9()\"'\\-]+%.vim") do
        local session = convert.to_path(k)
        if session:match(marker) then
            local session_name = session:match("[(](.+)[)]")
            session = session:match(marker .. "[(].+[)](.*)")
            table.insert(sessions, { name = session_name, path = session })
        end
    end
    return sessions
end

---@param session_path string
---@return string | nil
M._get_session_name = function(session_path)
    local consts = require("sessions.consts")
    local convert = require("sessions.convert")

    local command = "find " ..
        consts.path .. " -type f -name '" .. consts.marker .. "*" .. convert.from_path(session_path) .. ".vim'"
    local res = vim.fn.system(command)
    if not res or res == "" then
        return nil
    end
    local result = convert.to_path(res)
    local start_pos = result:find(consts.marker .. "%(")
    local end_pos = result:find("%)/", start_pos)
    if start_pos == nil or end_pos == nil then
        return nil
    end
    local name = result:sub(start_pos + #consts.marker + 1, end_pos - 1)
    return convert.to_path(name)
end

---@return Session
M.current = function()
    local path = vim.fn.getcwd()
    return {
        path = path,
        name = M._get_session_name(path)
    }
end

return M
