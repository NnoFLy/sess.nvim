local M = {}

local opts = {}

opts.marker = "FOR_MARKER"
opts.dirs = {}

function M.setup(user_opts)
    local commands = require("sessions.commands")

    if user_opts == nil then
        user_opts = {}
    end

    opts.path = user_opts.path or "~/sessions/"
    opts.attach_after_enter = user_opts.attach_after_enter or true
    opts.prompt_title = user_opts.prompt_title or "🗃️ All sessions"

    vim.cmd("silent !mkdir -p " .. opts.path)

    vim.api.nvim_create_user_command("SessionsList", function()
        commands.open_list()
    end, {})

    vim.api.nvim_create_user_command("SessionsRename", function()
        commands.rename_session()
    end, {})

    vim.api.nvim_create_user_command("SessionSave", function()
        commands.save_session()
    end, {})

    vim.api.nvim_create_user_command("SessionCreate", function()
        commands.create_session()
    end, {})

    vim.api.nvim_create_user_command("SessionAttach", function()
        local _, err = pcall(commands.attach_session)
        if err then
            print("Cann't found session here")
        end
    end, {})
end

function M.get_opts()
    return opts
end

return M
