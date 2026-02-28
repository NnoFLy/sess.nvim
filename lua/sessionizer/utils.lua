---@class sessionizer.Input
---@field user_input string
---@field result string

---@class sessionizer.PurgeOpts
---@field force boolean
---@field wipe boolean
---@field keep_scratch boolean

local M = {}

---@param opts sessionizer.PurgeOpts | nil
---@return nil
function M.purge_hidden_buffers(opts)
    local default_opts = {
        force = true,
        wipe = false,
        keep_scratch = false,
    }
    opts = vim.tbl_deep_extend("force", default_opts, opts or {})

    local bufs = vim.api.nvim_list_bufs()
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(scratch)

    for _, bufnr in ipairs(bufs) do
        if bufnr == scratch or not vim.api.nvim_buf_is_valid(bufnr) then
            goto continue
        end

        local ok, listed = pcall(vim.api.nvim_get_option_value, "buflisted", { buf = bufnr })
        if not ok or not listed then
            goto continue
        end

        if opts.wipe then
            ok = pcall(vim.api.nvim_buf_delete, bufnr, { force = opts.force })
            if not ok then
                pcall(vim.cmd, (opts.force and "silent! bwipeout! " or "silent! bwipeout ") .. bufnr)
            end
        else
            pcall(vim.api.nvim_buf_delete, bufnr, { force = opts.force })
        end

        ::continue::
    end

    local cur = vim.api.nvim_get_current_buf()
    if cur == scratch then
        vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
        pcall(vim.api.nvim_buf_delete, scratch, { force = true })
    end
end

---@return nil
function M.purge_term_buffers()
    for _, buf in pairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match("^term://") then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
end

function M.setup_auto_load()
    local commands = require("sessionizer.commands")
    local session = require("sessionizer.session")

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
    local commands = require("sessionizer.commands")
    local opts = require("sessionizer").get_opts()
    local state = require("sessionizer.state")

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

local commands_utils = require("sessionizer.commands._utils")

---@param a sessionizer.Session
---@param b sessionizer.Session
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

---@return sessionizer.Session[]
function M.get_items()
    local session = require("sessionizer.session")
    local state = require("sessionizer.state")
    local opts = require("sessionizer").get_opts()

    local all_sessions = session.get.all()
    local current_session = state.get_current_session()

    ---@type sessionizer.Session[]
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
