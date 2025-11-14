local ok, _ = pcall(require, "telescope")
if not ok then
    return
end

local M = {}

local pickers = require("telescope.pickers")
local dropdown = require("telescope.themes").get_dropdown()
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local opts = require("sessions").get_opts()

---@param prompt_bufnr number
function M.enter(prompt_bufnr)
    actions.close(prompt_bufnr)
    local selected = action_state.get_selected_entry()
    local session_name = selected[1]:gsub(" ", "_")
    local utils = require("sessions.utils")

    vim.cmd("cd " .. utils.get_session_path(opts.path, opts._marker, session_name))

    if opts.attach_after_enter then
        require("sessions.commands").attach_session()
    end
end

---@param prompt_bufnr number
function M.delete_session(prompt_bufnr)
    actions.close(prompt_bufnr)
    local selected = action_state.get_selected_entry()[1]
    local selected_copy = selected:sub(1, -1)
    selected = selected:gsub(" ", "_")
    local dir = opts._dirs[selected]
    local file = dir:gsub("/", ":"):sub(1, -1) .. ".vim"

    vim.cmd("silent !rm " .. opts.path .. file)
    vim.cmd(
        "silent !rm  "
        .. opts.path
        .. opts._marker
        .. "\\(" .. selected:gsub('"', '\\"'):sub(1, -1) .. "\\)"
        .. file
    )
    vim.notify("Session deleted: " .. selected_copy, vim.log.levels.INFO)
    vim.cmd("Sessions list")
end

---@param prompt_bufnr number
---@return boolean
function M.rename_session(prompt_bufnr)
    local utils = require("sessions.utils")

    actions.close(prompt_bufnr)
    local selected = action_state.get_selected_entry()[1]
    local selected_copy = selected:sub(1, -1)
    selected = selected:gsub(" ", "_")
    selected = selected:gsub('"', '\\"')
    local dir = opts._dirs[selected]
    local file = dir:gsub("/", ":"):sub(1, -1) .. ".vim"

    local new_name = utils.input("New name", selected_copy)
    if not new_name then
        vim.notify("Operation cancelled", vim.log.levels.INFO)
        return false
    end

    vim.cmd(
        "silent !mv "
        .. opts.path
        .. opts._marker
        .. "\\(" .. selected .. "\\)"
        .. file
        .. " "
        .. opts.path
        .. opts._marker
        .. "\\(" .. new_name.result .. "\\)"
        .. file
    )
    vim.notify("Session: " .. selected_copy .. " -> " .. new_name.user_input, vim.log.levels.INFO)
    vim.cmd("Sessions list")
    return true
end

function M.open_sessions_list()
    local telescope_utils = require("sessions.telescope.utils")
    pickers.new(
        dropdown,
        telescope_utils.get_options(opts.path, opts._marker, opts.prompt_title)
    ):find()
end

return M
