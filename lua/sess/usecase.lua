local function should_offer_save()
    local listed = 0
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_get_option_value("buflisted", { buf = bufnr }) then
            listed = listed + 1
        end
    end

    return not (listed <= 1 and vim.list_contains({ "netrw", "" }, vim.bo.filetype))
end

local M = {}

---@return Sess.Session?, string?
function M.do_u_wanna_save()
    if not should_offer_save() then
        return nil
    end

    local choice = vim.fn.confirm(
        "Do you want to save the current session?",
        "&Yes\n&No",
        2
    )
    if choice ~= 1 then
        return nil
    end

    local item, err = require("sess.session").get_by_path(vim.fn.getcwd())
    if err then
        return nil, err
    end

    return item
end

return M
