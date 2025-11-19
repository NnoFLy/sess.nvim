local M = {}

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

---@param path string
---@return string[]
function M.get_user_dirs(path)
    local home = os.getenv("HOME") or "~"
    local dirs = {}
    local command = "ls -d " .. path:gsub("~", home)
    local handle = io.popen(command)
    if handle then
        for dir in handle:lines() do
            table.insert(dirs, dir)
        end
        handle:close()
    end
    return dirs
end

return M
