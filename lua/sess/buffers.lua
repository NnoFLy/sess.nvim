local M = {}

---@alias Sess.BufferId integer

---@param bufnr Sess.BufferId
---@return boolean, boolean | string
function M.hide_buffer(bufnr)
    return pcall(vim.api.nvim_set_option_value, "buflisted", false, { buf = bufnr })
end

---@param bufnr Sess.BufferId
---@return boolean, boolean | string
function M.get_hidden_buffer_state(bufnr)
    return pcall(vim.api.nvim_get_option_value, "buflisted", { buf = bufnr })
end

---@return nil
function M.hide_all_buffers()
    local bufs = vim.api.nvim_list_bufs()
    local scratch = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(scratch)

    for _, bufnr in ipairs(bufs) do
        if bufnr == scratch or not vim.api.nvim_buf_is_valid(bufnr) then
            goto continue
        end

        local ok, listed = M.get_hidden_buffer_state(bufnr)
        if not ok or not listed then
            goto continue
        end

        M.hide_buffer(bufnr)

        ::continue::
    end

    local cur = vim.api.nvim_get_current_buf()
    if cur == scratch then
        vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))
        pcall(vim.api.nvim_buf_delete, scratch, { force = true })
    end
end

return M
