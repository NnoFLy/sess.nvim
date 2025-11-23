local M = {}

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local commands = require("sessionizer.commands")
local session = require("sessionizer.session")
local logger = require("sessionizer.logger")

---@param prompt_bufnr number
---@return nil
function M.enter(prompt_bufnr)
    actions.close(prompt_bufnr)

    local opts = require("sessionizer").get_opts()

    ---@type sessionizer.Session
    local selected_session = action_state.get_selected_entry().value

    if selected_session.last_used == 0 then
        commands.create(selected_session.name)
        return
    end

    commands.load(selected_session, opts.before_load, opts.after_load)
end

---@param prompt_bufnr number
---@return nil
function M.delete_session(prompt_bufnr)
    actions.close(prompt_bufnr)

    ---@type sessionizer.Session
    local selected_session = action_state.get_selected_entry().value

    if selected_session.last_used ~= 0 then
        if not commands.delete(selected_session) then
            logger.error("Failed to delete session")
        else
            logger.info("Session deleted: " .. selected_session.name)
        end
    else
        logger.warn("Session was never used: " .. selected_session.name)
    end
    commands.list()
end

---@param prompt_bufnr number
---@return nil
function M.rename_session(prompt_bufnr)
    actions.close(prompt_bufnr)

    ---@type sessionizer.Session
    local selected_session = action_state.get_selected_entry().value

    commands.pin(selected_session)
end

return M
