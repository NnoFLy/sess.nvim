local M = {}

---@param path string
---@return nil
function M.create_session(path)
    local session = require("sessionizer.session")
    local utils = require("sessionizer.utils")
    local logger = require("sessionizer.logger")
    local commands = require("sessionizer.commands")
    local state = require("sessionizer.state")

    local current_session = session.get.current()
    if current_session then
        commands.save()
        state.set_prev_session(current_session)
    end

    vim.fn.chdir(path)

    local ses = session.new()
    if not session.save(ses) then
        logger.error("Failed to create session")
        return
    end

    utils.purge_hidden_buffers()

    vim.cmd("e .")

    logger.info("Session created: " .. ses.name)
end

return M
