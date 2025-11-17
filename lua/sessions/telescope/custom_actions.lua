
local ok, _ = pcall(require, "telescope")
if not ok then
    local utils = require("sessions.utils")
    utils.notify("You need to install telescope.nvim for this command", vim.log.levels.ERROR)
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

    local session = require("sessions.session")
    local commands = require("sessions.commands")
    local opts = require("sessions").get_opts()

    local selected = action_state.get_selected_entry()
    local session_name = selected[1]

    local ses = session.get.by_name(session_name)
    if not ses then
        commands.create(session_name)
        return
    end

    commands.load(ses.name, opts.before_load, opts.after_load)
end

---@param prompt_bufnr number
---@return nil
function M.delete_session(prompt_bufnr)
    actions.close(prompt_bufnr)

    local session = require("sessions.session")
    local commands = require("sessions.commands")

    local selected = action_state.get_selected_entry()
    local session_name = selected[1]

    local ses = session.get.by_name(session_name)
    if not ses then
        return
    end

    session.delete(ses)
    commands.list()
end

---@param prompt_bufnr number
---@return nil
function M.rename_session(prompt_bufnr)
    actions.close(prompt_bufnr)

    local commands = require("sessions.commands")

    local selected = action_state.get_selected_entry()
    local session_name = selected[1]

    commands.pin(session_name)
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
