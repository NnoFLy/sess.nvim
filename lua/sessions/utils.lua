---@class Input
---@field user_input string
---@field result string

local M = {}

---@param prompt string
---@param default_value string
---@return Input | nil
function M.input(prompt, default_value)
    local convert = require("sessions.convert")
    local default = default_value and convert.to_path(default_value) or ""
    local input = vim.fn.input(prompt .. ": ", default)
    if not input then
        return
    end
    local result = input:sub(1, -1)
    local copy = result:sub(1, -1)
    result = convert.from_path(result)
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

---@return string[]
function M.get_modified_buffers()
    local modified = {}

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr)
            and vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
            and vim.api.nvim_get_option_value("modified", { buf = bufnr })
            and vim.api.nvim_buf_get_name(bufnr) ~= "" then
            table.insert(modified, vim.api.nvim_buf_get_name(bufnr))
        end
    end

    return modified
end

---@param msg string
---@param level number
function M.notify(msg, level)
    vim.notify("Sessions.nvim: " .. msg, level)
end

---@param value string
---@param arr string[]
---@return string | nil
function M.contains(value, arr)
    for _, v in ipairs(arr) do
        if v == value then
            return v
        end
    end
end

---@param str string
---@returns string[]
function M.split(str, sep)
    local t = {}
    local start = 1
    local sep_start, sep_end = str:find(sep, start)
    while sep_start do
        table.insert(t, str:sub(start, sep_start - 1))
        start = sep_end + 1
        sep_start, sep_end = str:find(sep, start)
    end
    table.insert(t, str:sub(start))
    return t
end

---@class PurgeOpts
---@field force boolean
---@field wipe boolean
---@field keep_scratch boolean

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

    for _, bufnr in ipairs(bufs) do
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
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local name = vim.api.nvim_buf_get_name(buf)
        if name:match("^term://") then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end
end

return M
