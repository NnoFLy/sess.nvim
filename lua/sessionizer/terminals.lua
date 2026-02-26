local M = {}

---@class sessionizer.Terminal
---@field bufnr integer
---@field buffer_name string

local function is_term_buf(bufnr)
    if not vim.api.nvim_buf_is_valid(bufnr) then return false end
    return vim.api.nvim_buf_get_name(bufnr):match("^term://") ~= nil
end

local function set_buflisted(bufnr, value)
    pcall(vim.api.nvim_set_option_value, "buflisted", value, { buf = bufnr })
end

---@param terminals sessionizer.Terminal[]|nil
---@param fn fun(bufnr: integer, name: string, term: sessionizer.Terminal)
local function with_valid_terms(terminals, fn)
    if not terminals or #terminals == 0 then return end

    for _, term in ipairs(terminals) do
        local bufnr = term.bufnr
        if vim.api.nvim_buf_is_valid(bufnr) then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name:match("^term://") then
                fn(bufnr, name, term)
            end
        end
    end
end

---@return sessionizer.Terminal[]
function M.get_term_buffers()
    local terminals = {}
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if is_term_buf(bufnr) then
            local ok, listed = pcall(vim.api.nvim_get_option_value, "buflisted", { buf = bufnr })
            if ok and listed then
                local name = vim.api.nvim_buf_get_name(bufnr)
                terminals[#terminals + 1] = { bufnr = bufnr, buffer_name = name }
            end
        end
    end
    return terminals
end

---@param terminals sessionizer.Terminal[]
---@return sessionizer.Terminal[]
function M.filter_valid_terminals(terminals)
    local valid = {}
    with_valid_terms(terminals, function(bufnr, name)
        valid[#valid + 1] = { bufnr = bufnr, buffer_name = name }
    end)
    return valid
end

---@param terminals sessionizer.Terminal[]
function M.hide_term_buffers(terminals)
    with_valid_terms(terminals, function(bufnr)
        set_buflisted(bufnr, false)
    end)
end

---@param terminals sessionizer.Terminal[]
function M.unhide_term_buffers(terminals)
    with_valid_terms(terminals, function(bufnr)
        set_buflisted(bufnr, true)
    end)
end

return M
