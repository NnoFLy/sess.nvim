local M = {}

local is_loaded = false

local logger = require("sess.logger")
local opts = require("sess.default_opts")

---@param user_opts Sess.Opts
function M.setup(user_opts)
    if is_loaded then
        return
    end

    local consts = require("sess.consts")
    local file = require("sess.file")
    local utils = require("sess.utils")

    if user_opts ~= nil then
        opts = vim.tbl_deep_extend("force", opts, user_opts)
    end

    if not file.create_dir(consts.path) then
        logger.error("Failed to create sess directory")
    end

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
