local M = {}

local window = require("sess.ui.window")

local loaded = false
local configured

local defaults = {
    paths = {},
    smart_auto_load = true,
    auto_save = true,
    log_level = "info",
    exclude_filetypes = { "gitcommit" },
    store_path = vim.fn.stdpath("data") .. "/sess.nvim",
    hooks = {},
    keymap = {
        prefix = "<C-q>",
        set_mark = "<C-q>",
        edit_marks = "<C-e>",
    },
    mark_window = window.defaults(),
}

local function keycode(value)
    return vim.api.nvim_replace_termcodes(value, true, false, true)
end

local function validate_keymap(keymap)
    if type(keymap) ~= "table" then
        return false, "keymap must be a table"
    end

    local seen = {}
    for name, value in pairs(keymap) do
        if name ~= "prefix" and name ~= "set_mark" and name ~= "edit_marks" then
            return false, "unknown keymap option: " .. tostring(name)
        end
        if type(value) ~= "string" or value == "" then
            return false, "keymap." .. name .. " must be a non-empty key specification"
        end

        local normalized = keycode(value)
        if normalized == "" then
            return false, "keymap." .. name .. " must be a non-empty key specification"
        end
        if name ~= "prefix" then
            if seen[normalized] then
                return false, "keymap entries conflict: " .. seen[normalized] .. " and " .. name
            end
            seen[normalized] = name
        end
    end

    for _, name in ipairs({ "prefix", "set_mark", "edit_marks" }) do
        if keymap[name] == nil then
            return false, "keymap." .. name .. " must be a non-empty key specification"
        end
    end

    return true
end

function M.validate_hooks(hooks)
    if type(hooks) ~= "table" then
        return false, "hooks must be a table"
    end

    for name, callback in pairs(hooks) do
        if name ~= "before_transition" and name ~= "after_operation" then
            return false, "unknown hook: " .. tostring(name)
        end

        if type(callback) ~= "function" then
            return false, "hooks." .. name .. " must be a function"
        end
    end

    return true
end

function M.setup(user_opts)
    if loaded then
        return false, "sess.nvim is already loaded"
    end

    if user_opts ~= nil and type(user_opts) ~= "table" then
        return false, "options must be a table"
    end

    for name in pairs(user_opts or {}) do
        if defaults[name] == nil then
            return false, "unknown option: " .. tostring(name)
        end
    end

    local ok, candidate =
        pcall(vim.tbl_deep_extend, "force", vim.deepcopy(defaults), user_opts or {})
    if not ok then
        return false, tostring(candidate)
    end

    local valid_window, window_err = window.validate(candidate.mark_window)
    if not valid_window then
        return false, window_err
    end

    if type(candidate.keymap) ~= "table" then
        return false, "keymap must be a table"
    end

    -- Keep the old popup `open` option useful as the edit action unless the
    -- new top-level keymap explicitly overrides it.
    local user_keymap = user_opts and user_opts.keymap
    if not user_keymap or user_keymap.edit_marks == nil then
        candidate.keymap.edit_marks = candidate.mark_window.keymap.open
    end

    local valid_keymap, keymap_err = validate_keymap(candidate.keymap)
    if not valid_keymap then
        return false, keymap_err
    end

    for _, name in ipairs({ "paths", "exclude_filetypes" }) do
        if type(candidate[name]) ~= "table" or not vim.islist(candidate[name]) then
            return false, name .. " must be a list"
        end

        for _, value in ipairs(candidate[name]) do
            if type(value) ~= "string" or vim.trim(value) == "" then
                return false, name .. " entries must be non-empty strings"
            end
        end
    end

    if not ({ debug = true, info = true, warn = true, error = true })[candidate.log_level] then
        return false, "log_level must be debug, info, warn or error"
    end

    if type(candidate.auto_save) ~= "boolean" or type(candidate.smart_auto_load) ~= "boolean" then
        return false, "auto_save and smart_auto_load must be boolean"
    end

    local valid, err = M.validate_hooks(candidate.hooks)
    if not valid then
        return false, err
    end

    local called, ok, storage_err = pcall(require("sess.storage").init, candidate.store_path)
    if not called then
        return false, tostring(ok)
    end

    if not ok then
        return false, storage_err
    end

    local installed, install_err = require("sess.ui.marks").setup_keymap(candidate.keymap)
    if not installed then
        return false, install_err
    end

    configured = candidate
    require("sess.autocmd").setup(candidate)
    loaded = true

    return true
end

function M.is_setup()
    return loaded
end

function M.get()
    return vim.deepcopy(configured or defaults)
end

return M
