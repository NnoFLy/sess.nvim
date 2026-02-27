local M = {}

local logger = require("sessionizer.logger")
local state = require("sessionizer.state")
local terminals = require("sessionizer.terminals")
local session = require("sessionizer.session")

---@return nil
function M.hide_all_term_buffers()
    local current_session = state.get_current_session()
    if current_session then
        local filtred_terms = terminals.filter_valid_terminals(terminals.get_term_buffers())
        state.set_terminals(current_session, filtred_terms)
        terminals.hide_term_buffers(filtred_terms)
    end
    logger.debug("All terminal buffers hidden")
end

---@return nil
function M.unhide_all_term_buffers()
    local current_session = state.get_current_session()
    if not current_session then return end

    local stored_terminals = terminals.filter_valid_terminals(state.get_terminals(current_session))
    state.set_terminals(current_session, stored_terminals)
    if #stored_terminals > 0 then
        terminals.unhide_term_buffers(stored_terminals)
        logger.debug("Terminals restored: " .. tostring(#stored_terminals))
    end
end

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
