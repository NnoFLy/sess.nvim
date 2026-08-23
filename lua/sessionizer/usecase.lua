local M = {}

local session = require("sessionizer.session")

---@return sessionizer.Session | nil
function M.do_u_wanna_save()
    local buffers_count = 0
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.bo[buf].buflisted then
            buffers_count = buffers_count + 1
        end
    end

    if buffers_count <= 1 and vim.list_contains({ "netrw", "" }, vim.bo.filetype) then
        return nil
    end

    local choice = vim.fn.confirm("Do you want to save the current session?", "&Yes\n&No", 2)
    if choice ~= 1 then
        return nil
    end

    local cwd = vim.loop.cwd()
    if not cwd then
        return nil
    end

    return session.get.by_path(cwd)
end

return M
