local M = {}

local is_loaded = false

---@type sessionizer.Opts
local opts = require("sessionizer.default_opts")

---@param user_opts sessionizer.Opts
function M.setup(user_opts)
    if is_loaded then
        return
    end

    local consts = require("sessionizer.consts")
    local file = require("sessionizer.file")
    local utils = require("sessionizer.utils")

    if user_opts ~= nil then
        opts = vim.tbl_deep_extend("force", opts, user_opts)
    end

    file.create_dir(consts.path)

    if opts.smart_auto_load then
        utils.setup_auto_load()
    end

    if opts.auto_save then
        utils.setup_auto_save()
    end

    is_loaded = true
end

function M.get_opts()
    return opts
end

return M
