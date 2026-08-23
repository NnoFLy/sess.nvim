---@class Sess.BeforeLoadOpts
---@field auto_save_files boolean
---@field auto_hide_buffers boolean
---@field custom function

---@class Sess.AfterLoadOpts
---@field custom function

---@class Sess.OnUnloadOpts
---@field custom function

---@alias Sess.log_level "debug"|"info"|"warn"|"error"

---@class Sess.Opts
---@field paths string[]
---@field log_level Sess.log_level
---@field smart_auto_load boolean
---@field auto_save boolean
---@field exclude_filetypes string[]
---@field auto_save_files boolean
---@field before_load Sess.BeforeLoadOpts
---@field after_load Sess.AfterLoadOpts
---@field on_unload Sess.OnUnloadOpts
return {
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
}
