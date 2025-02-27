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
    local dir = selected[1]:gsub(" ", "_")

    vim.cmd("cd " .. opts.dirs[dir])

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
    local dir = opts.dirs[selected]
    local file = dir:gsub("/", ":"):sub(1, -1) .. ".vim"

    vim.cmd("silent !rm -rf " .. opts.path .. file)
    vim.cmd(
        "silent !rm -rf "
        .. opts.path
        .. opts.marker
        .. "\\(" .. selected:gsub('"', '\\"'):sub(1, -1) .. "\\)"
        .. file
    )
    print("Session deleted: " .. selected_copy)
    vim.cmd("SessionsList")
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
    local dir = opts.dirs[selected]
    local file = dir:gsub("/", ":"):sub(1, -1) .. ".vim"

    local new_name = utils.input("New name", selected_copy)
    if not new_name then
        print("Operation cancelled")
        return false
    end

    vim.cmd(
        "silent !mv "
        .. opts.path
        .. opts.marker
        .. "\\(" .. selected .. "\\)"
        .. file
        .. " "
        .. opts.path
        .. opts.marker
        .. "\\(" .. new_name.result .. "\\)"
        .. file
    )
    print("Session: " .. selected_copy .. " -> " .. new_name.user_input)
    vim.cmd("SessionsList")
    return true
end

function M.open_sessions_list()
    local utils = require("sessions.utils")
    pickers.new(dropdown, utils.get_options()):find()
end

return M
