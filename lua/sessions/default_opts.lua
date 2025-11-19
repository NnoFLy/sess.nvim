---@class BeforeLoadOpts
---@field auto_save_files boolean
---@field auto_remove_buffers boolean
---@field custom function

---@class AfterLoadOpts
---@field custom function

---@class Opts
---@field prompt_title string
---@field paths string[]
---@field smart_auto_load boolean
---@field smart_auto_save boolean
---@field exclude_filetypes string[]
---@field auto_save_files boolean
---@field before_load BeforeLoadOpts
---@field after_load AfterLoadOpts
return {
    prompt_title = "🗃️ All sessions",
    paths = {},
    smart_auto_load = true,
    smart_auto_save = true,
    exclude_filetypes = { "gitcommit" },
    before_load = {
        auto_save_files = false,
        auto_remove_buffers = false,
        custom = function() end,
    },
    after_load = {
        custom = function() end,
    }
}
