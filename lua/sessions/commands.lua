local M = {}

local telescope_custom_actions = require("sessions.telescope_custom_actions")
local opts = require("sessions").get_opts()

function M.attach_session()
    vim.cmd("silent source " .. opts.path .. vim.fn.getcwd():gsub("/", ":") .. ".vim")
end

function M.save_session()
    vim.cmd("mksession! " .. opts.path .. vim.fn.getcwd():gsub("/", ":") .. ".vim")
end

function M.create_session()
    M.save_session()
    local prompt = vim.fn.input("Enter Session Name: ")
    local prompt_copy = prompt:sub(1, -1)
    if prompt == "" then
        return
    end
    prompt = prompt:gsub(" ", "_")
    prompt = prompt:gsub('"', '\\"')
    vim.cmd(
        "silent !touch "
        .. opts.path
        .. opts.marker
        .. "\\(" .. prompt .. "\\)"
        .. vim.fn.getcwd():gsub("/", ":")
        .. ".vim"
    )
    print("Session created: " .. prompt_copy)
end

function M.open_list()
    telescope_custom_actions.open_sessions_list()
end

return M
