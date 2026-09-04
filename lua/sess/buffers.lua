local M = {}

---@alias Sess.BufferId integer

---@param bufnr Sess.BufferId
---@return boolean, string?
function M.hide_buffer(bufnr)
    local ok, err = pcall(vim.api.nvim_set_option_value, "buflisted", false, { buf = bufnr })
    if not ok then
        return false, tostring(err)
    end
    return true
end

---@param bufnr Sess.BufferId
---@return boolean, boolean | string
function M.get_hidden_buffer_state(bufnr)
    return pcall(vim.api.nvim_get_option_value, "buflisted", { buf = bufnr })
end

---@return boolean, string?
function M.hide_all_buffers()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr)
            and vim.api.nvim_buf_is_loaded(bufnr)
            and vim.api.nvim_get_option_value("buflisted", { buf = bufnr })
        then
            local ok, err = M.hide_buffer(bufnr)
            if not ok then
                return false, err
            end
        end
    end

    return true
end

return M
