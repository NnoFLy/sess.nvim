---@class Sess.Input
---@field user_input string
---@field result string

---@class Sess.PurgeOpts
---@field force boolean
---@field wipe boolean
---@field keep_scratch boolean

local M = {}

function M.setup_auto_load()
    local commands = require("sess.commands")
    local session = require("sess.session")

    vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
            vim.schedule(function()
                if vim.fn.argc() ~= 0 then
                    return
                end

                local cwd = vim.fn.getcwd()
                local s = session.get.by_path(cwd)
                if s then
                    commands.load(s)
                else
                    commands.create(cwd)
                end
            end)
        end,
    })
end

function M.setup_auto_save()
    local commands = require("sess.commands")
    local opts = require("sess").get_opts()
    local state = require("sess.state")

    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            if vim.list_contains(opts.exclude_filetypes, vim.bo.filetype) then
                return
            end
            if not state.get_current_session() then
                return
            end
            commands.save()
        end
    })
end

local commands_utils = require("sess.commands._utils")

---@param a Sess.Session
---@param b Sess.Session
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

---@return Sess.Session[]
function M.get_items()
    local session = require("sess.session")
    local state = require("sess.state")
    local opts = require("sess").get_opts()

    local all_sessions = session.get.all()
    local current_session = state.get_current_session()

    ---@type Sess.Session[]
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

    local user_paths = opts.paths
    if type(user_paths) ~= "table" then
        user_paths = {}
    end

    for _, path in pairs(user_paths) do
        for _, dir in ipairs(commands_utils.get_user_dirs(path)) do
            if not vim.list_contains(paths, dir) then
                table.insert(items, { name = dir, path = dir, last_used = 0 })
            end
        end
    end

    return items
end

return M
