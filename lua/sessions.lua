---@class Hooks
---@field pre_hook function
---@field post_hook function

local M = {}

---@type Opts
local opts = require("sessions.default_opts")

---@param user_opts Opts
function M.setup(user_opts)
    local commands = require("sessions.commands")
    local consts = require("sessions.consts")

    if user_opts ~= nil then
        opts = vim.tbl_deep_extend("force", opts, user_opts)
    end

    vim.cmd("silent !mkdir -p " .. consts.path)

    M.builtins = commands

    return M
end

function M.get_opts()
    return opts
end

return M
