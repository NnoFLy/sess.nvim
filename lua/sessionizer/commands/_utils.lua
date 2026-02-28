local M = {}

---@param s sessionizer.Session
---@return boolean
function M.is_pinned(s)
    return s.name ~= s.path
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

    for _, bufnr in pairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr)
            and vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
            and vim.api.nvim_get_option_value("modified", { buf = bufnr })
            and vim.api.nvim_buf_get_name(bufnr) ~= "" then
            table.insert(modified, vim.api.nvim_buf_get_name(bufnr))
        end
    end

    return modified
end

---@param path string
---@return string[]
function M.get_user_dirs(path)
    if type(path) ~= "string" or path == "" then
        return {}
    end

    local home = os.getenv("HOME") or "~"
    local dirs = {}
    local patterns = vim.fn.glob(path:gsub("~", home), false, true)
    for _, dir in ipairs(patterns) do
        if vim.fn.isdirectory(dir) == 1 then
            table.insert(dirs, dir)
        end
    end
    return dirs
end

return M
