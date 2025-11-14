---@class Builtins
---@field attach fun(session: Session | nil): boolean
---@field completion fun(): string[]
---@field get_current fun(): Session
---@field open_list fun()
---@field pin fun()
---@field save fun(): boolean
---@field setup fun()

---@class Hooks
---@field pre_hook function
---@field post_hook function

---@alias SessionsList string[]

local M = {}

---@class Opts
local opts = {}

---@param user_opts Opts
function M.setup(user_opts)
    local commands = require("sessions.commands")

    local default_opts = require("sessions.default_opts")
    if user_opts ~= nil then
        opts = vim.tbl_deep_extend("force", default_opts, user_opts)
    else
        opts = default_opts
    end

    vim.cmd("silent !mkdir -p " .. opts.path)

    M.open_list = commands.open_list
    M.save = commands.save_session
    M.pin = commands.pin_session
    M.create = commands.pin_session
    M.attach = commands.attach_session
    M.get_current = commands.get_current
    M.open_last = commands.open_last

    return M
end

function M.get_opts()
    return opts
end

return M
