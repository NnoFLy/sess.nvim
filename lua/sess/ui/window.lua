local M = {}

local positions = {
    left_top = true,
    center_top = true,
    right_top = true,
    left_center = true,
    center = true,
    right_center = true,
    left_bottom = true,
    center_bottom = true,
    right_bottom = true,
}

local borders = {
    none = true,
    single = true,
    double = true,
    rounded = true,
    solid = true,
    shadow = true,
}

local win_option_defaults = {
    cursorline = true,
    winblend = 0,
    winhighlight = "",
}

local keymap_defaults = {
    open = "<C-e>",
    load_prefix = "g",
    delete = "d",
    undo = "u",
    change_mark = "r",
    rename = "R",
}

function M.defaults()
    return {
        position = "right_bottom",
        width = 48,
        height = 10,
        margin = 1,
        border = "rounded",
        title = " Marks ",
        title_pos = "center",
        win_options = vim.deepcopy(win_option_defaults),
        keymap = vim.deepcopy(keymap_defaults),
    }
end

local function finite_integer(value, minimum)
    return type(value) == "number"
        and value == math.floor(value)
        and value < math.huge
        and value >= minimum
end

local function validate_win_options(options)
    if type(options) ~= "table" then
        return false, "mark_window.win_options must be a table"
    end

    for name, value in pairs(options) do
        if win_option_defaults[name] == nil then
            return false, "unknown mark_window.win_options option: " .. tostring(name)
        end
        if name == "cursorline" and type(value) ~= "boolean" then
            return false, "mark_window.win_options.cursorline must be boolean"
        end
        if
            name == "winblend" and not finite_integer(value, 0)
            or name == "winblend" and value > 100
        then
            return false, "mark_window.win_options.winblend must be an integer from 0 to 100"
        end
        if name == "winhighlight" and type(value) ~= "string" then
            return false, "mark_window.win_options.winhighlight must be a string"
        end
    end

    return true
end

local function keycode(value)
    return vim.api.nvim_replace_termcodes(value, true, false, true)
end

local function validate_keymap(keymap)
    if type(keymap) ~= "table" then
        return false, "mark_window.keymap must be a table"
    end

    local seen = {}
    for name in pairs(keymap_defaults) do
        local value = keymap[name]
        if type(value) ~= "string" or value == "" then
            return false, "mark_window.keymap." .. name .. " must be a non-empty key specification"
        end
        local normalized = keycode(value)
        if normalized == "" then
            return false, "mark_window.keymap." .. name .. " must be a non-empty key specification"
        end
        if seen[normalized] then
            return false,
                "mark_window.keymap entries conflict: " .. seen[normalized] .. " and " .. name
        end
        seen[normalized] = name
    end

    for name in pairs(keymap) do
        if keymap_defaults[name] == nil then
            return false, "unknown mark_window.keymap option: " .. tostring(name)
        end
    end

    return true
end

-- This accepts both a user partial and a fully merged configuration. Keeping
-- it here avoids making the options module a dependency of the window owner.
function M.validate(options)
    if type(options) ~= "table" then
        return false, "mark_window must be a table"
    end

    local allowed = {
        position = true,
        width = true,
        height = true,
        margin = true,
        border = true,
        title = true,
        title_pos = true,
        win_options = true,
        keymap = true,
    }
    for name in pairs(options) do
        if not allowed[name] then
            return false, "unknown mark_window option: " .. tostring(name)
        end
    end

    if options.position ~= nil and not positions[options.position] then
        return false, "mark_window.position must be one of the supported placements"
    end
    if options.width ~= nil and not finite_integer(options.width, 1) then
        return false, "mark_window.width must be a finite positive integer"
    end
    if options.height ~= nil and not finite_integer(options.height, 1) then
        return false, "mark_window.height must be a finite positive integer"
    end
    if options.margin ~= nil and not finite_integer(options.margin, 0) then
        return false, "mark_window.margin must be a finite nonnegative integer"
    end
    if options.border ~= nil and not borders[options.border] then
        return false, "mark_window.border must be none, single, double, rounded, solid, shadow"
    end
    if options.title ~= nil then
        if type(options.title) ~= "string" or options.title:find("[\r\n]") then
            return false, "mark_window.title must be a single-line string"
        end
    end
    if
        options.title_pos ~= nil
        and options.title_pos ~= "left"
        and options.title_pos ~= "center"
        and options.title_pos ~= "right"
    then
        return false, "mark_window.title_pos must be left, center or right"
    end

    if options.win_options ~= nil then
        local valid, err = validate_win_options(options.win_options)
        if not valid then
            return false, err
        end
    end
    if options.keymap ~= nil then
        return validate_keymap(options.keymap)
    end

    return true
end

local function normalize(options)
    if type(options) ~= "table" then
        return nil, "mark_window must be a table"
    end
    local called, merged = pcall(vim.tbl_deep_extend, "force", M.defaults(), options)
    if not called then
        return nil, tostring(merged)
    end
    local valid, err = M.validate(merged)
    if not valid then
        return nil, err
    end
    return merged
end

local function border_size(border)
    return border == "none" and 0 or 2
end

local function editor_dimensions()
    local ui = vim.api.nvim_list_uis()[1]
    local width = ui and ui.width or vim.o.columns
    local height = ui and ui.height or vim.o.lines
    local tabline = vim.o.showtabline == 0 and 0 or 1
    local statusline = 0
    if vim.o.laststatus == 2 or vim.o.laststatus == 3 then
        statusline = 1
    elseif vim.o.laststatus == 1 and #vim.api.nvim_list_wins() > 1 then
        statusline = 1
    end

    return {
        width = width,
        height = height - tabline - vim.o.cmdheight - statusline,
        top = tabline,
    }
end

local function screen_value(screen, name, fallback)
    if screen and screen[name] ~= nil then
        return screen[name]
    end
    return fallback
end

-- Return an nvim_open_win configuration. `screen` is injectable to keep the
-- placement rules independent from a particular UI size in tests.
function M.geometry(options, screen)
    local resolved, err = normalize(options)
    if not resolved then
        return nil, err
    end
    options = resolved

    local dimensions = editor_dimensions()
    local screen_width = screen_value(screen, "width", dimensions.width)
    local screen_height = screen_value(screen, "height", dimensions.height)
    local top = screen and (screen.top or 0) or dimensions.top
    local border = border_size(options.border)
    local usable_width = screen_width
    local usable_height = screen_height

    local content_width = math.min(options.width, usable_width - border)
    local content_height = math.min(options.height, usable_height - border)
    if content_width < 1 or content_height < 1 then
        return nil, "mark_window border cannot fit a minimum content area"
    end

    local outer_width = content_width + border
    local outer_height = content_height + border
    local available_margin = math.floor(
        math.min(
            math.max(0, usable_width - outer_width) / 2,
            math.max(0, usable_height - outer_height) / 2
        )
    )
    local margin = math.min(options.margin, available_margin)
    local horizontal = options.position:match("^(%w+)_") or options.position
    local vertical = options.position:match("_(%w+)$")
    if options.position == "center" then
        horizontal, vertical = "center", "center"
    end

    local col
    if horizontal == "left" then
        col = margin
    elseif horizontal == "right" then
        col = usable_width - outer_width - margin
    else
        col = math.floor((usable_width - outer_width) / 2)
    end

    local row
    if vertical == "top" then
        row = margin
    elseif vertical == "bottom" then
        row = usable_height - outer_height - margin
    else
        row = math.floor((usable_height - outer_height) / 2)
    end

    return {
        relative = "editor",
        row = top + row,
        col = col,
        width = content_width,
        height = content_height,
        border = options.border,
        style = "minimal",
        title = options.border == "none" and nil or options.title,
        title_pos = options.border == "none" and nil or options.title_pos,
        focusable = true,
    }
end

local function set_buffer_option(buf, name, value)
    vim.api.nvim_set_option_value(name, value, { buf = buf })
end

local function set_window_option(win, name, value)
    vim.api.nvim_set_option_value(name, value, { win = win })
end

local function cleanup(buf, win)
    local errors = {}
    if win and vim.api.nvim_win_is_valid(win) then
        local ok, err = pcall(vim.api.nvim_win_close, win, true)
        if not ok then
            errors[#errors + 1] = tostring(err)
        end
    end
    if buf and vim.api.nvim_buf_is_valid(buf) then
        local ok, err = pcall(vim.api.nvim_buf_delete, buf, { force = true })
        if not ok then
            errors[#errors + 1] = tostring(err)
        end
    end
    return #errors == 0, #errors > 0 and table.concat(errors, "; ") or nil
end

function M.open(options, focus)
    local resolved, resolve_err = normalize(options)
    if not resolved then
        return nil, resolve_err
    end
    local config, geometry_err = M.geometry(resolved)
    if not config then
        return nil, geometry_err
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.b[buf].sess_mark_window = true
    local win
    local ok, err = pcall(function()
        set_buffer_option(buf, "buftype", "nofile")
        set_buffer_option(buf, "bufhidden", "wipe")
        set_buffer_option(buf, "swapfile", false)
        set_buffer_option(buf, "modifiable", true)
        win = vim.api.nvim_open_win(buf, focus ~= false, config)
        set_window_option(win, "number", false)
        set_window_option(win, "relativenumber", false)
        set_window_option(win, "signcolumn", "no")
        set_window_option(win, "foldcolumn", "0")
        set_window_option(win, "wrap", false)
        for name, value in pairs(resolved.win_options) do
            set_window_option(win, name, value)
        end
        set_buffer_option(buf, "modifiable", false)
    end)
    if not ok then
        local cleaned, cleanup_err = cleanup(buf, win)
        if not cleaned then
            err = tostring(err) .. "; cleanup failed: " .. cleanup_err
        end
        return nil, tostring(err)
    end

    return {
        buf = buf,
        win = win,
        options = vim.deepcopy(resolved),
        geometry = vim.deepcopy(config),
    }
end

function M.update(handle, options)
    if type(handle) ~= "table" or not vim.api.nvim_win_is_valid(handle.win) then
        return false, "mark window is no longer valid"
    end
    local resolved, resolve_err = normalize(options or handle.options)
    if not resolved then
        return false, resolve_err
    end
    local config, err = M.geometry(resolved)
    if not config then
        return false, err
    end
    local ok, update_err = pcall(vim.api.nvim_win_set_config, handle.win, config)
    if not ok then
        return false, tostring(update_err)
    end
    handle.options = vim.deepcopy(resolved)
    handle.geometry = vim.deepcopy(config)
    return true
end

function M.close(handle)
    if type(handle) ~= "table" then
        return true
    end
    return cleanup(handle.buf, handle.win)
end

function M.is_valid(handle)
    return type(handle) == "table"
        and vim.api.nvim_win_is_valid(handle.win)
        and vim.api.nvim_buf_is_valid(handle.buf)
end

return M
