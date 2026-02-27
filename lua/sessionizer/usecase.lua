local M = {}

local logger = require("sessionizer.logger")
local state = require("sessionizer.state")
local terminals = require("sessionizer.terminals")

function M.hide_all_term_buffers()
    local current_session = state.get_current_session()
    if current_session then
        local filtred_terms = terminals.filter_valid_terminals(terminals.get_term_buffers())
        state.set_terminals(current_session, filtred_terms)
        terminals.hide_term_buffers(filtred_terms)
    end
    logger.debug("All terminal buffers hidden")
end

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

return M
