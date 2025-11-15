---@class Input
---@field user_input string
---@field result string

local M = {}

---@param path string
---@param marker string
---@return Session[]
function M.get_sessions(path, marker)
    local sessions = {}
    for k, _ in vim.fn.execute("!ls " .. path):gmatch("[A-Za-z_.%%:|0-9()\"'\\-]+%.vim") do
        local session = M.to_path(k)
        if session:match(marker) then
            local session_name = session:match("[(](.+)[)]")
            session = session:match(marker .. "[(].+[)](.*)")
            table.insert(sessions, { name = session_name, path = session })
        end
    end
    return sessions
end

---@param name string
---@return Session | nil
function M.get_session_by_name(name)
    local consts = require("sessions.consts")
    local sessions = M.get_sessions(consts.path, consts.marker)
    for _, session in ipairs(sessions) do
        if session.name == name then
            return session
        end
    end
    return nil
end

---@param prompt string
---@param default_value string
---@return Input | nil
function M.input(prompt, default_value)
    local default = default_value and M.to_path(default_value) or ""
    local input = vim.fn.input(prompt .. ": ", default)
    if not input then
        return
    end
    local result = input:sub(1, -1)
    local copy = result:sub(1, -1)
    result = M.from_path(result)
    if not result then
        return nil
    end
    return {
        user_input = copy,
        result = result,
    }
end

---@param path string
---@return string
function M.get_last_folder_in_path(path)
    if path:sub(-1) == '/' then
        path = path:sub(1, -2)
    end
    local last = path:match(".*/(.*)")
    return last or path
end

---@param marker string
---@param name string
---@return string
function M.add_marker(marker, name)
    return marker .. "%p" .. name .. "%P"
end

---@param path string
---@return string | nil
function M.remove_marker(path)
    local colon_pos = path:find(":")
    if colon_pos then
        return ":" .. path:sub(colon_pos + 1)
    end
end

local convert_chars = {
    ["/"] = ':',
    ["%("] = "%%p",
    ["%)"] = "%%P",
    [" "] = "_",
    ['"'] = '%%q',
}

---@param path string
---@return string
function M.from_path(path)
    local result = path
    for k, v in pairs(convert_chars) do
        result = result:gsub(k, v)
    end
    return result
end

---@param path string
---@return string
function M.to_path(path)
    local result = path
    for k, v in pairs(convert_chars) do
        result = result:gsub(v, k)
    end
    return result
end

---@param file string
---@param session Session | nil
---@return string
M.make_file_name = function(file, session)
    local home = os.getenv("HOME") or "~"
    local consts = require("sessions.consts")

    if session == nil then
        local file_name = consts.path .. file
        file_name = file_name:gsub("^~", home)
        return file_name
    end

    local file_name = consts.path
        .. consts.marker
        .. M.from_path("(" .. session.name .. ")")
        .. file
    file_name = file_name:gsub("^~", home)
    return file_name
end

return M
