local M = {}

---@param a Sess.Session
---@param b Sess.Session
---@return boolean
local function compare_sessions(a, b)
    if a.metadata.pinned ~= b.metadata.pinned then
        return a.metadata.pinned
    end

    if a.metadata.last_used_at ~= b.metadata.last_used_at then
        return a.metadata.last_used_at > b.metadata.last_used_at
    end

    local an = a.metadata.name:lower()
    local bn = b.metadata.name:lower()
    if an ~= bn then
        return an < bn
    end

    return a.metadata.cwd < b.metadata.cwd
end

---@param path string
---@return string[]
local function get_user_paths(path)
    if type(path) ~= "string" or path == "" then
        return {}
    end

    local home = os.getenv("HOME") or "~"
    local dirs = {}
    local patterns = vim.fn.glob(path:gsub("~", home), false, true)
    for _, dir in ipairs(patterns) do
        if vim.fn.isdirectory(dir) == 1 then
            table.insert(dirs, vim.fs.normalize(dir))
        end
    end
    return dirs
end

---@class Sess.DirectoryItem
---@field name string
---@field path string
---@field last_used_at Sess.Timestamp
---@field pinned boolean

---@return (Sess.Session|Sess.DirectoryItem)[]
function M.get_items()
    local session = require("sess.session")
    local state = require("sess.state")
    local opts = require("sess").get_opts()

    local all_sessions = session.list()
    local current_session = state.get_current_session()

    ---@type (Sess.Session|Sess.DirectoryItem)[]
    local items = {}
    local paths = {}

    if current_session then
        table.insert(items, current_session)
        table.insert(paths, current_session.metadata.cwd)
    end

    for _, s in ipairs(all_sessions) do
        if not current_session or vim.fs.normalize(current_session.metadata.cwd) ~= vim.fs.normalize(s.metadata.cwd) then
            table.insert(items, s)
            table.insert(paths, s.metadata.cwd)
        end
    end

    local user_paths = type(opts.paths) == "table" and opts.paths or {}
    for _, pattern in ipairs(user_paths) do
        for _, dir in ipairs(get_user_paths(pattern)) do
            local exists = false
            for _, path in ipairs(paths) do
                if vim.fs.normalize(path) == dir then
                    exists = true
                    break
                end
            end

            if not exists then
                table.insert(items, {
                    name = vim.fn.fnamemodify(dir, ":t"),
                    path = dir,
                    last_used_at = 0,
                    pinned = false,
                })
                table.insert(paths, dir)
            end
        end
    end

    table.sort(items, function(a, b)
        local a_is_session = a.metadata ~= nil
        local b_is_session = b.metadata ~= nil
        if a_is_session and b_is_session then
            return compare_sessions(a, b)
        end
        if a_is_session ~= b_is_session then
            return a_is_session
        end
        return a.name:lower() < b.name:lower()
    end)

    if current_session then
        for i, item in ipairs(items) do
            if item.metadata and item.id == current_session.id then
                table.remove(items, i)
                break
            end
        end
        table.insert(items, 1, current_session)
    end

    return items
end

return M
