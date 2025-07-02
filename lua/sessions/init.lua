---@class Hooks
---@field pre_hook function
---@field post_hook function

---@alias SessionsList string[] List of sessions

---@class Opts
---@field path string | nil
---@field attach_after_enter boolean | nil
---@field prompt_title string | nil
---@field _dirs SessionsList | nil
---@field _marker string | nil

local M = {}

---@type Opts
local opts = {}

opts._marker = "FOR_MARKER"
opts._dirs = {}

function M.setup(user_opts)
    local commands = require("sessions.commands")

    if user_opts == nil then
        user_opts = {}
    end

    opts.path = user_opts.path or "~/sessions/"
    opts.attach_after_enter = not (user_opts.attach_after_enter or false)
    opts.prompt_title = user_opts.prompt_title or "🗃️ All sessions"

    vim.cmd("silent !mkdir -p " .. opts.path)

    vim.api.nvim_create_user_command("SessionsList", function()
        commands.open_list()
    end, {})

    vim.api.nvim_create_user_command("SessionSave", function()
        commands.save_session()
    end, {})

    vim.api.nvim_create_user_command("SessionCreate", function()
        commands.pin_session()
    end, {})

    vim.api.nvim_create_user_command("SessionPin", function()
        commands.pin_session()
    end, {})

    local completion = require("sessions.utils").generate_completion(opts.path, opts._marker)
    vim.api.nvim_create_user_command("SessionAttach", function(input)
        if input.args and #input.args > 0 then
            local args = input.args
            local ok = commands.attach_session({ name = args })
            if not ok then
                print("Session doesn't exist: " .. args)
            end
        else
            local ok = commands.attach_session()
            if not ok then
                print("Cann't found session here")
            end
        end
    end, {
        nargs = "?",
        complete = completion
    })

    M.list = commands.open_list
    M.save = commands.save_session
    M.pin = commands.pin_session
    M.create = commands.pin_session
    M.attach = commands.attach_session
    M.get_current = commands.get_current
    M.completion = completion

    return M
end

function M.get_opts()
    return opts
end

return M
