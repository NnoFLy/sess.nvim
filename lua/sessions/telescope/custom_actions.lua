local ok, _ = pcall(require, "telescope")
if not ok then
    return
end

local M = {}

local pickers = require("telescope.pickers")
local dropdown = require("telescope.themes").get_dropdown()
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local consts = require("sessions.consts")

---@param prompt_bufnr number
---@return nil
function M.enter(prompt_bufnr)
    local convert = require("sessions.convert")

    actions.close(prompt_bufnr)
    local selected = action_state.get_selected_entry()
    local session_name = convert.from_path(selected[1])
    require("sessions.commands").load(session_name)
end

---@param prompt_bufnr number
---@return nil
function M.delete_session(prompt_bufnr)
    local convert = require("sessions.convert")
    actions.close(prompt_bufnr)
    local selected = action_state.get_selected_entry()
    local session_name = convert.from_path(selected[1])
    require("sessions.commands").delete(session_name)
    require("sessions.commands").list()
end

---@param prompt_bufnr number
---@return nil
function M.rename_session(prompt_bufnr)
    local convert = require("sessions.convert")
    actions.close(prompt_bufnr)
    local selected = action_state.get_selected_entry()
    local session_name = convert.from_path(selected[1])
    require("sessions.commands").rename(session_name)
end

---@param prompt_title string
---@return nil
function M.open_sessions_list(prompt_title)
    local telescope_utils = require("sessions.telescope.utils")
    pickers.new(
        dropdown,
        telescope_utils.get_options(consts.path, consts.marker, prompt_title)
    ):find()
end

return M
