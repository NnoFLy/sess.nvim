---@class Session
---@field name string
---@field path string
---@field last_used number

local M = {
    get = {},
}

local file = require("sessionizer.file")
local consts = require("sessionizer.consts")
local logger = require("sessionizer.logger")

---@param file_name string
---@return Session | nil
local function parse_file_name(file_name)
    local parts = vim.split(file_name, consts.separators.main)

    ---@type string
    local p = parts[2]
    if not p then
        return nil
    end
    local path = p:gsub(consts.separators.path, "/")

    local n = parts[1]
    if not n then
        return nil
    end
    local name = n:gsub(consts.separators.path, "/")

    return {
        name = name,
        path = path,
        last_used = tonumber(parts[3])
    }
end

---@param session Session
---@return string
local function to_file_name(session)
    local path = table.concat(
        vim.split(session.path, "/"),
        consts.separators.path
    )
    local name = table.concat(
        vim.split(session.name, "/"),
        consts.separators.path
    )
    if not name or name == "" then
        name = path
    end

    ---@type Session
    local local_session = {
        name = name,
        path = path,
        last_used = session.last_used,
    }

    local session_str =
        consts.prefix
        .. local_session.name
        .. consts.separators.main
        .. local_session.path
        .. consts.separators.main
        .. local_session.last_used

    return session_str
end

---@param session Session
---@return Session | nil
function M.load(session)
    local s = M.get.by_name(session.name)
    if not s then
        return nil
    end

    local str = "silent source " .. consts.path .. to_file_name(s)
    local ok, msg = pcall(function() vim.cmd(str) end)
    if not ok and msg and msg:gmatch("Can't re-enter normal mode from terminal mode") then
        return s
    end
    if not ok then
        logger.error("Message: " .. msg)
        return nil
    end
    return s
end

---@param name string | nil
---@param cwd string | nil
---@return Session
function M.new(name, cwd)
    cwd = cwd or vim.fn.getcwd()

    ---@type Session
    local session = {
        name = name or cwd,
        path = cwd,
        last_used = os.time(),
    }
    return session
end

---@param session Session
---@return boolean
function M.save(session)
    local s = M.get.by_name(session.name)

    if s then
        local file_path = to_file_name(s)
        file.delete(consts.path .. file_path)
        session.name = s.name
    end
    local file_path = to_file_name(session)
    local ok = file.mksession(consts.path .. file_path)
    if not ok then
        return false
    end
    return true
end

---@param session Session
---@param new_session Session
---@return boolean
function M.rename(session, new_session)
    local s = M.get.by_name(session.name)
    if not s then
        return false
    end

    local file_path = consts.path .. to_file_name(s)
    local new_name = consts.path .. to_file_name(new_session)

    local ok = file.rename(file_path, new_name)
    if not ok then
        return false
    end
    return true
end

---@param session Session
---@return boolean
function M.delete(session)
    local s = M.get.by_name(session.name)
    if not s then
        return false
    end

    local file_path = consts.path .. to_file_name(s)
    local ok = file.delete(file_path)
    if not ok then
        return false
    end
    return true
end

---@param name string
---@return Session | nil
function M.get.by_name(name)
    local sessions = M.get.all()
    for _, session in pairs(sessions) do
        if session.name == name then
            return session
        end
    end
    return nil
end

---@param path string
---@return Session | nil
function M.get.by_path(path)
    local sessions = M.get.all()
    for _, session in pairs(sessions) do
        if session.path == path then
            return session
        end
    end
    return nil
end

---@return Session[]
function M.get.all()
    local sessions = {}
    for file_name, _ in vim.fn.execute("!ls " .. consts.path):gmatch(consts.prefix .. "[^\n]+") do
        local parsed = file_name:sub(#consts.prefix + 1)
        local session = parse_file_name(parsed)
        if session then
            table.insert(sessions, session)
        end
    end
    return sessions
end

return M
