---@class Opts
---@field path string | nil
---@field attach_after_enter boolean | nil
---@field prompt_title string | nil
---@field dirs string[] | nil
---@field marker string | nil

local M = {}

---@type Opts
local opts = {}

opts.marker = "FOR_MARKER"
opts.dirs = {}

function M.setup(user_opts)
    local commands = require("sessions.commands")

    if user_opts == nil then
        user_opts = {}
    end

    opts.path = user_opts.path or "~/sessions/"
    opts.attach_after_enter = user_opts.attach_after_enter
    opts.prompt_title = user_opts.prompt_title or "🗃️ All sessions"

    vim.cmd("silent !mkdir -p " .. opts.path)

    vim.api.nvim_create_user_command("SessionsList", function()
        commands.open_list()
    end, {})

    vim.api.nvim_create_user_command("SessionSave", function()
        commands.save_session()
    end, {})

    vim.api.nvim_create_user_command("SessionCreate", function()
        commands.create_session()
    end, {})

    vim.api.nvim_create_user_command("SessionAttach", function()
        local ok, _ = pcall(commands.attach_session)
        if not ok then
            print("Cann't found session here")
        end
    end, {})

    M.open_list = commands.open_list
    M.save_session = commands.save_session
    M.create_session = commands.create_session
    M.attach_session = commands.attach_session

    return M
end

function M.get_opts()
    return opts
end

return M
