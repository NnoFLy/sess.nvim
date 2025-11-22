---@class Input
---@field user_input string
---@field result string

---@class PurgeOpts
---@field force boolean
---@field wipe boolean
---@field keep_scratch boolean

local M = {}

---@param opts PurgeOpts | nil
---@return nil
function M.purge_hidden_buffers(opts)
    local default_opts = {
        force = false,
        wipe = false,
        keep_scratch = false,
    }
    opts = vim.tbl_deep_extend("force", default_opts, opts or {})

    local api = vim.api
    local bufs = api.nvim_list_bufs()
    local scratch = api.nvim_create_buf(false, true)
    api.nvim_set_current_buf(scratch)

    for _, bufnr in pairs(bufs) do
        if bufnr ~= scratch and api.nvim_buf_is_valid(bufnr) then
            if opts.wipe then
                local ok = pcall(api.nvim_buf_delete, bufnr, { force = true })
                if not ok then
                    pcall(function() vim.cmd("bwipeout! " .. bufnr) end)
                end
            else
                local name = vim.api.nvim_buf_get_name(bufnr)
                if name:match("^term://") then
                    goto continue
                end
                pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
            end
        end
        ::continue::
    end

    if not opts.keep_scratch then
        local cur = api.nvim_get_current_buf()
        if cur == scratch then
            api.nvim_set_current_buf(api.nvim_create_buf(true, false))
        end
        pcall(api.nvim_buf_delete, scratch, { force = true })
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
                if vim.fn.argc() == 0 then
                    local s = session.get.by_path(vim.fn.getcwd())
                    if s then
                        commands.load(s)
                    end
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

return M
