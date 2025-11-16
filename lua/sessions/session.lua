---@class Session
---@field name string
---@field path string
---@field last_used number

---@class GetByOpts
---@field path string

local M = {
    get = {},
}

local file = require("sessions.file")
local utils = require("sessions.utils")
local consts = require("sessions.consts")

---@param file_name string
---@return Session
local function parse_file_name(file_name)
    local parts = utils.split(file_name, consts.separators.main)

    local path = table.concat(utils.split(parts[2], consts.separators.path), "/")
    local name = table.concat(utils.split(parts[1], consts.separators.path), "/")

    return {
        name = name,
        path = path,
        last_used = tonumber(parts[3])
    }
end

---@param session Session
---@return string
local function to_file_name(session)
    ---@type Session
    local local_session = {
        name = table.concat(
            utils.split(session.name, "/"),
            consts.separators.path
        ),
        path = table.concat(
            utils.split(session.path, "/"),
            consts.separators.path
        ),
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
    local str = "silent source " .. consts.path .. to_file_name(session)
    local ok, _ = pcall(function() vim.cmd(str) end)
    if not ok then
        return nil
    end
    return session
end

---@param name string | nil
---@return Session
function M.new(name)
    local cwd = vim.fn.getcwd()

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
    local exists_session = M.get.by_path(session.path)
    local file_path = to_file_name(exists_session or session)
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
    local file_path = consts.path .. to_file_name(session)
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
    local file_path = consts.path .. to_file_name(session)
    local ok = file.delete(file_path)
    if not ok then
        return false
    end
    return true
end

---@param name string
---@param opts GetByOpts | nil
---@return Session | nil
function M.get.by_name(name, opts)
    opts = opts or {}

    local sessions = M.get.all(opts.path or consts.path)
    for _, session in ipairs(sessions) do
        if session.name == name then
            return session
        end
    end
    return nil
end

---@param path string | nil
---@param opts GetByOpts | nil
---@return Session | nil
function M.get.by_path(path, opts)
    opts = opts or {}

    local sessions = M.get.all(opts.path or consts.path)
    for _, session in ipairs(sessions) do
        if session.path == path then
            return session
        end
    end
    return nil
end

---@param path string | nil
---@return Session[]
function M.get.all(path)
    path = path or consts.path

    local sessions = {}
    for file_name, _ in vim.fn.execute("!ls " .. path):gmatch(consts.prefix .. "[^\n]+") do
        local parsed = file_name:sub(#consts.prefix + 1)
        local session = parse_file_name(parsed)
        table.insert(sessions, session)
    end
    return sessions
end

---@return Session | nil
M.get.current = function()
    local path = vim.fn.getcwd()
    local session = M.get.by_path(path)
    return session
end

return M
