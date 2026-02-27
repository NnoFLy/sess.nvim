local utils = require("sessionizer.utils")
local logger = require("sessionizer.logger")
local state = require("sessionizer.state")
local session = require("sessionizer.session")
local usecase = require("sessionizer.usecase")

---@param path string | nil
---@return nil
return function(path)
    local commands = require("sessionizer.commands")

    local current_session = state.get_current_session()
    if not current_session then
        current_session = usecase.do_u_wanna_save()
    end

    if current_session then
        commands.save()
        usecase.hide_all_term_buffers()
    end

    path = path or vim.fn.getcwd()
    path = vim.fn.expand(path)

    if vim.fn.isdirectory(path) == 0 then
        logger.error("Directory does not exist: " .. path)
        return false
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
    vim.g.sessionizer_current_session = s.name

    logger.info("Session created: " .. s.name)
end
