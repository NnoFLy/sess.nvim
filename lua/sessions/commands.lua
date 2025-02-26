local M = {}

local telescope_custom_actions = require("sessions.telescope_custom_actions")
local opts = require("sessions").get_opts()
local utils = require("sessions.utils")

function M.attach_session()
    vim.cmd("silent source " .. opts.path .. vim.fn.getcwd():gsub("/", ":") .. ".vim")
end

function M.save_session()
    vim.cmd("mksession! " .. opts.path .. vim.fn.getcwd():gsub("/", ":") .. ".vim")
end

function M.create_session()
    M.save_session()
    local prompt = utils.input("Enter Session Name: ")
    if not prompt then
        return
    end

    vim.cmd(
        "silent !touch "
        .. opts.path
        .. opts.marker
        .. "\\(" .. prompt.result .. "\\)"
        .. vim.fn.getcwd():gsub("/", ":")
        .. ".vim"
    )
    print("Session created: " .. prompt.user_input)
end

function M.open_list()
    telescope_custom_actions.open_sessions_list()
end

return M
