local ok, _ = pcall(require, "telescope")
if not ok then
    require("sessions.logger").error("You need to install telescope.nvim for this command")
    return
end

local M = {}

local pickers = require("telescope.pickers")
local dropdown = require("telescope.themes").get_dropdown()
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

---@param prompt_bufnr number
---@return nil
function M.enter(prompt_bufnr)
    actions.close(prompt_bufnr)

    local commands = require("sessions.commands")
    local opts = require("sessions").get_opts()

    ---@type Session
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

    local session = require("sessions.session")
    local commands = require("sessions.commands")
    local logger = require("sessions.logger")

    ---@type Session
    local selected_session = action_state.get_selected_entry().value

    if selected_session.last_used ~= 0 then
        session.delete(selected_session)
        logger.info("Session deleted: " .. selected_session.name)
    else
        logger.warn("Session was never used: " .. selected_session.name)
    end
    commands.list()
end

---@param prompt_bufnr number
---@return nil
function M.rename_session(prompt_bufnr)
    actions.close(prompt_bufnr)

    local commands = require("sessions.commands")

    ---@type Session
    local selected_session = action_state.get_selected_entry().value

    commands.pin(selected_session)
end

---@param prompt_title string
---@return nil
function M.open_sessions_list(prompt_title)
    local telescope_utils = require("sessions.telescope.utils")

    pickers.new(
        dropdown,
        telescope_utils.get_options(telescope_utils.get_items(), prompt_title)
    ):find()
end

return M
