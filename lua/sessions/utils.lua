---@class Input
---@field user_input string
---@field result string

local M = {}

---@param path string
---@param marker string
---@return SessionsList
function M.get_sessions(path, marker)
    local sessions = {}
    for k, _ in vim.fn.execute("!ls " .. path):gmatch("[A-Za-z_.:|0-9()\"'\\-]+.vim") do
        local session = k:gsub(":", "/"):sub(1, -5)
        if session:match(marker) then
            local session_name = session:match("[(](.+)[)]")
            session = session:match(marker .. "[(].+[)](.*)")
            sessions[session_name] = session
        end
    end
    return sessions
end

---@param path string
---@param marker string
---@param name string
---@return string
function M.get_session_path(path, marker, name)
    local sessions = M.get_sessions(path, marker)
    return sessions[name]
end

---@param prompt string
---@param default_value string
---@return Input | nil
function M.input(prompt, default_value)
    local default = default_value and default_value:gsub("_", " ") or ""
    local copy, result
    vim.ui.input({ prompt = prompt .. ": ", default = default}, function(input)
        if not input then
            return
        end
        result = input:sub(1, -1)
        copy = result:sub(1, -1)
        result = result:gsub(" ", "_"):gsub("'", "\\'")
    end)
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
    return marker .. "(" .. name .. ")"
end

---@param path string
---@return string | nil
function M.remove_marker(path)
    local colon_pos = path:find(":")
    if colon_pos then
        return ":" .. path:sub(colon_pos + 1)
    end
end

---@param path string
---@return string
function M.antiparse(path)
    local result = path:gsub("/", ":")
    result = result:gsub(" ", "_")
    result = result:gsub('"', '\\"')
    return result
end

---@param path string
---@return string
function M.parse(path)
    local result = path:gsub(":", "/")
    result = result:gsub("_", " ")
    result = result:gsub('\\"', '"')
    return result
end

return M
