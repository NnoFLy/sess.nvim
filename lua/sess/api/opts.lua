local M = {}

local window = require("sess.ui.window")

local loaded = false
local configured

local defaults = {
    paths = {},
    smart_auto_load = "current",
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
    tabline = { enabled = true },
    sidebar = {
        enabled = true,
        start_open = false,
        position = "left",
        width = 32,
        min_width = 24,
        max_width = 48,
        active_expand = "all",
        toggle_key = false,
        refresh_interval = 1000,
        mouse = true,
    },
}

local function keycode(value)
    return vim.api.nvim_replace_termcodes(value, true, false, true)
end

local function validate_sidebar(sidebar)
    if type(sidebar) ~= "table" then
        return false, "sidebar must be a table"
    end
    local known = {
        enabled = true,
        start_open = true,
        position = true,
        width = true,
        min_width = true,
        max_width = true,
        active_expand = true,
        toggle_key = true,
        refresh_interval = true,
        mouse = true,
    }
    for name in pairs(sidebar) do
        if not known[name] then
            return false, "unknown sidebar option: " .. tostring(name)
        end
    end
    for _, name in ipairs({ "enabled", "start_open", "mouse" }) do
        if type(sidebar[name]) ~= "boolean" then
            return false, "sidebar." .. name .. " must be boolean"
        end
    end
    if sidebar.position ~= "left" and sidebar.position ~= "right" then
        return false, "sidebar.position must be left or right"
    end
    if
        sidebar.active_expand ~= "all"
        and sidebar.active_expand ~= "current"
        and sidebar.active_expand ~= "none"
    then
        return false, "sidebar.active_expand must be all, current or none"
    end
    for _, name in ipairs({ "width", "min_width", "max_width", "refresh_interval" }) do
        local value = sidebar[name]
        if type(value) ~= "number" or value % 1 ~= 0 or value <= 0 then
            return false, "sidebar." .. name .. " must be a positive integer"
        end
    end
    if sidebar.min_width > sidebar.max_width then
        return false, "sidebar.min_width must not exceed sidebar.max_width"
    end
    if sidebar.toggle_key ~= false then
        local key = sidebar.toggle_key
        if type(key) ~= "string" or key == "" or keycode(key) == "" then
            return false, "sidebar.toggle_key must be false or a non-empty key specification"
        end
    end
    return true
end

M.validate_sidebar = validate_sidebar

local function validate_tabline(tabline)
    if type(tabline) ~= "table" then
        return false, "tabline must be a table"
    end
    for name in pairs(tabline) do
        if name ~= "enabled" then
            return false, "unknown tabline option: " .. tostring(name)
        end
    end
    if type(tabline.enabled) ~= "boolean" then
        return false, "tabline.enabled must be boolean"
    end
    return true
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

    local valid_sidebar, sidebar_err = validate_sidebar(candidate.sidebar)
    if not valid_sidebar then
        return false, sidebar_err
    end

    local valid_tabline, tabline_err = validate_tabline(candidate.tabline)
    if not valid_tabline then
        return false, tabline_err
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

    if type(candidate.auto_save) ~= "boolean" then
        return false, "auto_save must be boolean"
    end

    if
        candidate.smart_auto_load ~= "none"
        and candidate.smart_auto_load ~= "current"
        and candidate.smart_auto_load ~= "all"
    then
        return false, "smart_auto_load must be none, current or all"
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
    loaded = true
    require("sess.autocmd").setup(candidate)
    require("sess.ui.sidebar").configure(candidate.sidebar)
    if candidate.tabline.enabled then
        require("sess.ui.tabline").install()
    end
    if candidate.sidebar.start_open then
        vim.schedule(function()
            if not loaded then
                return
            end
            local opened, open_err = require("sess.ui.sidebar").open()
            if not opened then
                require("sess.log").error(open_err or "failed to open sidebar")
            end
        end)
    end

    return true
end

function M.is_setup()
    return loaded
end

function M.get()
    return vim.deepcopy(configured or defaults)
end

return M
