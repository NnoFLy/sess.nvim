---@class Sess.BeforeLoadOpts
---@field auto_save_files boolean
---@field auto_hide_buffers boolean
---@field custom function

---@class Sess.AfterLoadOpts
---@field custom function

---@class Sess.OnUnloadOpts
---@field custom function

---@alias Sess.log_level "debug"|"info"|"warn"|"error"

---@alias Sess.DBPath string

---@class Sess.Opts
---@field paths string[]
---@field log_level Sess.log_level
---@field smart_auto_load boolean
---@field auto_save boolean
---@field exclude_filetypes string[]
---@field before_load Sess.BeforeLoadOpts
---@field after_load Sess.AfterLoadOpts
---@field on_unload Sess.OnUnloadOpts
---@field store_path Sess.DBPath

local M = {}

local is_loaded = false

local log = require("sess.log")
local storage = require("sess.storage")
local autocmd = require("sess.autocmd")

---@type Sess.Opts
local opts = {
    paths = {},
    smart_auto_load = true,
    auto_save = true,
    log_level = "info",
    exclude_filetypes = { "gitcommit" },
    before_load = {
        auto_save_files = false,
        auto_hide_buffers = true,
        custom = function() end,
    },
    after_load = {
        custom = function() end,
    },
    on_unload = {
        custom = function() end,
    },
    store_path = vim.fn.stdpath("data") .. "/sess.nvim"
}

---@param user_opts Sess.Opts
function M.setup(user_opts)
    if is_loaded then
        log.error("Sess.nvim is already loaded")
        return
    end

    if user_opts ~= nil then
        opts = vim.tbl_deep_extend("force", opts, user_opts)
    end

    local ok, err = storage.init(opts.store_path)

    if not ok then
        log.error(err or "Cannot initialize storage")
        return
    end

    -- TODO: Create a user's sessions from `opts.paths`

    if opts.smart_auto_load then
        autocmd.setup_auto_load()
    end

    if opts.auto_save then
        autocmd.setup_auto_save()
    end

    is_loaded = true
end

function M.get_opts()
    return opts
end

return M
