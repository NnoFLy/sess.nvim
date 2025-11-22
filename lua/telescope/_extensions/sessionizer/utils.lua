local commands_utils = require("sessionizer.commands._utils")

local M = {}

---@param a Session
---@param b Session
---@return boolean
local function compare_sessions(a, b)
    local pa, pb = commands_utils.is_pinned(a), commands_utils.is_pinned(b)
    if pa ~= pb then
        return pa
    end

    local a_has_custom_name = a.name ~= a.path
    local b_has_custom_name = b.name ~= b.path
    if a_has_custom_name ~= b_has_custom_name then
        return a_has_custom_name
    end

    if a.last_used ~= b.last_used then
        return a.last_used > b.last_used
    end

    if a.name ~= b.name then
        return a.name < b.name
    end

    return a.path < b.path
end

---@return Session[]
function M.get_items()
    local session = require("sessionizer.session")
    local state = require("sessionizer.state")
    local opts = require("sessionizer").get_opts()

    local all_sessions = session.get.all()
    local current_session = state.get_current_session()

    ---@type Session[]
    local items = {}
    ---@type string[]
    local paths = {}

    if current_session then
        table.insert(paths, current_session.path)
    end

    for _, ses in ipairs(all_sessions) do
        if current_session and current_session.path == ses.path then
            goto continue
        end

        table.insert(items, ses)
        table.insert(paths, ses.path)

        ::continue::
    end

    table.sort(items, compare_sessions)

    if current_session then
        table.insert(items, 1, current_session)
    end

    for _, path in pairs(opts.paths) do
        for _, dir in ipairs(commands_utils.get_user_dirs(path)) do
            if not vim.list_contains(paths, dir) then
                table.insert(items, { name = dir, path = dir, last_used = 0 })
            end
        end
    end

    return items
end

return M
