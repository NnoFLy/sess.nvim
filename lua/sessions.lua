---@class Hooks
---@field pre_hook function
---@field post_hook function

local M = {}

---@type Opts
local opts = {}

---@param user_opts Opts
function M.setup(user_opts)
    local commands = require("sessions.commands")
    local consts = require("sessions.consts")

    local default_opts = require("sessions.default_opts")
    if user_opts ~= nil then
        opts = vim.tbl_deep_extend("force", default_opts, user_opts)
    else
        opts = default_opts
    end

    vim.cmd("silent !mkdir -p " .. consts.path)

    M.builtins = commands

    return M
end

function M.get_opts()
    return opts
end

return M
