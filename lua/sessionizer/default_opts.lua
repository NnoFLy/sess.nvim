---@class sessionizer.BeforeLoadOpts
---@field auto_save_files boolean
---@field auto_remove_buffers boolean
---@field custom function

---@class sessionizer.AfterLoadOpts
---@field custom function

---@class sessionizer.OnUnloadOpts
---@field custom function

---@alias sessionizer.log_level "debug"|"info"|"warn"|"error"

---@class sessionizer.Opts
---@field paths string[]
---@field log_level sessionizer.log_level
---@field smart_auto_load boolean
---@field auto_save boolean
---@field exclude_filetypes string[]
---@field auto_save_files boolean
---@field before_load sessionizer.BeforeLoadOpts
---@field after_load sessionizer.AfterLoadOpts
---@field on_unload sessionizer.OnUnloadOpts
return {
    paths = {},
    smart_auto_load = true,
    auto_save = true,
    log_level = "info",
    exclude_filetypes = { "gitcommit" },
    before_load = {
        auto_save_files = false,
        auto_remove_buffers = false,
        custom = function() end,
    },
    after_load = {
        custom = function() end,
    },
    on_unload = {
        custom = function() end,
    },
}
