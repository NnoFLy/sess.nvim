local M = {}

local is_loaded = false

---@type Opts
local opts = require("sessions.default_opts")

---@param user_opts Opts
function M.setup(user_opts)
    if is_loaded then
        return
    end

    local consts = require("sessions.consts")
    local file = require("sessions.file")
    local utils = require("sessions.utils")

    if user_opts ~= nil then
        opts = vim.tbl_deep_extend("force", opts, user_opts)
    end

    file.create_dir(consts.path)

    if opts.smart_auto_load then
        utils.setup_auto_load()
    end

    if opts.smart_auto_save then
        utils.setup_auto_save()
    end

    is_loaded = true
end

function M.get_opts()
    return opts
end

return M
