local M = {}
local storage = require("sess.storage")

local loaded = false

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

---@type Sess.Opts
local defaults = {
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
    store_path = vim.fn.stdpath("data") .. "/sess.nvim",
}

local function validate(opts)
    if type(opts.paths) ~= "table" then
        return false, "paths must be a table"
    end
    for i, path in ipairs(opts.paths) do
        if type(path) ~= "string" or vim.trim(path) == "" then
            return false, "paths[" .. i .. "] must be a non-empty string"
        end
    end
    if type(opts.log_level) ~= "string" or not ({ debug = true, info = true, warn = true, error = true })[opts.log_level] then
        return false, "log_level must be one of debug, info, warn, error"
    end
    if type(opts.smart_auto_load) ~= "boolean" or type(opts.auto_save) ~= "boolean" then
        return false, "smart_auto_load and auto_save must be boolean"
    end
    if type(opts.exclude_filetypes) ~= "table" then
        return false, "exclude_filetypes must be a table"
    end
    for i, filetype in ipairs(opts.exclude_filetypes) do
        if type(filetype) ~= "string" then
            return false, "exclude_filetypes[" .. i .. "] must be a string"
        end
    end
    if type(opts.store_path) ~= "string" or vim.trim(opts.store_path) == "" then
        return false, "store_path must be a non-empty string"
    end

    for group_name, group in pairs({
        before_load = opts.before_load,
        after_load = opts.after_load,
        on_unload = opts.on_unload,
    }) do
        if type(group) ~= "table" or type(group.custom) ~= "function" then
            return false, group_name .. ".custom must be a function"
        end
    end

    if type(opts.before_load.auto_save_files) ~= "boolean"
        or type(opts.before_load.auto_hide_buffers) ~= "boolean"
    then
        return false, "before_load.auto_save_files and auto_hide_buffers must be boolean"
    end

    return true
end

---@param user_opts Sess.Opts?
---@return boolean, string?
function M.setup(user_opts)
    if loaded then
        return false, "sess.nvim is already loaded"
    end

    local candidate = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})
    local valid, err = validate(candidate)
    if not valid then
        return false, err
    end

    local ok, storage_err = storage.init(candidate.store_path)
    if not ok then
        return false, storage_err or "cannot initialize storage"
    end

    M._opts = candidate

    require("sess.autocmd").setup(candidate)

    loaded = true

    return true
end

---@return boolean
function M.is_setup()
    return loaded
end

---@return Sess.Opts
function M.get()
    return vim.deepcopy(M._opts or defaults)
end

return M
