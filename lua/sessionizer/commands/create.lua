---@param path string
---@return nil
return function(path)
    local utils = require("sessionizer.utils")
    local logger = require("sessionizer.logger")
    local commands = require("sessionizer.commands")
    local state = require("sessionizer.state")
    local session = require("sessionizer.session")

    local current_session = state.get_current_session()
    if current_session then
        commands.save()
    end

    vim.fn.chdir(path)

    utils.purge_hidden_buffers()

    vim.cmd("e .")

    local s = session.new()
    if not session.save(s) then
        logger.error("Failed to create session")
        return
    end

    if current_session then
        state.set_prev_session(current_session)
    end
    state.set_current_session(s)

    logger.info("Session created: " .. s.name)
end
