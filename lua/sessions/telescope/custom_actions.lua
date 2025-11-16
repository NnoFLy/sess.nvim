
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

    local selected = action_state.get_selected_entry()
    local session_name = selected[1]

    local ses = session.get.by_name(session_name)
    if not ses then
        return
    end

    session.load(ses)
end

---@param prompt_bufnr number
---@return nil
function M.delete_session(prompt_bufnr)
    actions.close(prompt_bufnr)

    local session = require("sessions.session")

    local selected = action_state.get_selected_entry()
    local session_name = selected[1]

    local ses = session.get.by_name(session_name)
    if not ses then
        return
    end

    session.delete(ses)

    require("sessions.commands").list()
end

---@param prompt_bufnr number
---@return nil
function M.rename_session(prompt_bufnr)
    actions.close(prompt_bufnr)

    local session = require("sessions.session")

    local selected = action_state.get_selected_entry()
    local session_name = selected[1]

    local ses = session.get.by_name(session_name)
    if not ses then
        return
    end

    require("sessions.commands").pin()
end

---@param prompt_title string
---@return nil
function M.open_sessions_list(prompt_title)
    local telescope_utils = require("sessions.telescope.utils")
    local session = require("sessions.session")
    local all_sessions = session.get.all()

    local sessions_names = {}
    for _, ses in ipairs(all_sessions) do
        table.insert(sessions_names, ses.name)
    end

    pickers.new(
        dropdown,
        telescope_utils.get_options(sessions_names, prompt_title)
    ):find()
end

return M
