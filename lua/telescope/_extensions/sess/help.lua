local M = {}

local actions = require("telescope._extensions.sess.actions")

local descriptors = {
    regular = {
        [actions.enter] = {
            id = "enter",
            short = "switch",
            label = "Switch or create session",
        },
        [actions.toggle_pin_session] = {
            id = "pin",
            short = "pin",
            label = "Toggle pin",
        },
        [actions.mark_session] = {
            id = "mark",
            short = "mark",
            label = "Assign mark",
        },
        [actions.rename_session] = {
            id = "rename",
            short = "rename",
            label = "Rename",
        },
        [actions.unload_session] = {
            id = "unload",
            short = "unload",
            label = "Unload safely",
        },
        [actions.delete_session] = {
            id = "delete",
            short = "delete",
            label = "Delete with confirmation",
        },
    },
    active = {
        [actions.active_enter] = {
            id = "enter",
            short = "switch/focus",
            label = "Switch and focus agent",
        },
        [actions.toggle_active] = {
            id = "expand",
            short = "expand",
            label = "Toggle expansion",
        },
        [actions.toggle_all_active] = {
            id = "expand_all",
            short = "all",
            label = "Toggle all expansion",
        },
        [actions.mark_session] = {
            id = "mark",
            short = "mark",
            label = "Assign mark",
        },
    },
    restore = {
        [actions.restore_session] = {
            id = "restore",
            short = "restore",
            label = "Restore deleted session",
        },
    },
}

local function mode_name(mode)
    if mode == "i" or mode == "ic" or mode == "ix" then
        return "i"
    end
    return "n"
end

local function current_mode()
    local ok, mode = pcall(vim.fn.mode, 1)
    if ok then
        return mode_name(mode)
    end
    return "i"
end

local function display_width(value)
    local ok, width = pcall(vim.fn.strdisplaywidth, value)
    if ok then
        return width
    end
    return #value
end

local function shorten(value, width)
    if display_width(value) <= width then
        return value
    end
    if width <= 1 then
        return string.sub(value, 1, width)
    end
    local result = vim.fn.strcharpart(value, 0, width - 1) .. "…"
    return result
end

local function custom_description(custom, kind, mode, key, action, fallback)
    if type(custom) ~= "table" then
        return fallback
    end

    local value = custom[action]
    if value == nil then
        value = custom[key]
    end
    if value == nil and type(custom[kind]) == "table" then
        value = custom[kind][mode] and custom[kind][mode][key]
            or custom[kind][key]
    end
    if type(value) == "table" then
        value = value.label or value.help or value.short
    end
    return type(value) == "string" and value ~= "" and value or fallback
end

local function descriptor(kind, mode, key, action, custom)
    local known = descriptors[kind] and descriptors[kind][action]
    local fallback = known and known.label or "Run action"
    local label = custom_description(custom, kind, mode, key, action, fallback)
    local short = known and known.short or label
    if type(custom) == "table" then
        local value = custom[action] or custom[key]
        if type(value) == "table" and type(value.short) == "string" then
            short = value.short
        elseif type(value) == "string" then
            short = value
        end
    end
    return {
        id = known and known.id or key,
        key = key,
        action = action,
        short = short,
        label = label,
    }
end

local function selected_value()
    local ok, action_state = pcall(require, "telescope.actions.state")
    if not ok or type(action_state.get_selected_entry) ~= "function" then
        return nil
    end
    local selected_ok, selected = pcall(action_state.get_selected_entry)
    return selected_ok and selected and selected.value or nil
end

local function available(kind, item, value)
    if not value then
        return true
    end
    if kind == "regular" then
        if item.id == "enter" then
            return value.directory or value.id ~= nil
        end
        return value.id ~= nil
    elseif kind == "active" then
        if item.id == "expand_all" then
            return true
        end
        return value.kind == "session" or value.kind == "agent"
    elseif kind == "restore" then
        return value.id ~= nil or value.key ~= nil
    end
    return true
end

local function entries(kind, mode, mappings, custom, value, include_unavailable)
    local result = {}
    local mode_mappings = mappings and mappings[mode] or {}
    for key, action in pairs(mode_mappings) do
        if type(action) == "function" then
            local item = descriptor(kind, mode, key, action, custom)
            if include_unavailable or available(kind, item, value) then
                item.available = available(kind, item, value)
                result[#result + 1] = item
            end
        end
    end
    table.sort(result, function(left, right)
        return left.key < right.key
    end)
    return result
end

local function get_action_help(options)
    if not options or options.action_help == nil then
        return {}
    end
    return options.action_help
end

local function help_key(options)
    local action_help = get_action_help(options)
    if
        action_help == false
        or action_help.enabled == false
        or action_help.key == false
        or action_help.key == nil
    then
        return nil
    end
    return action_help.key
end

function M.entries(kind, mode, mappings, options, value)
    local action_help = get_action_help(options)
    local descriptions = type(action_help) == "table" and action_help.descriptions or nil
    return entries(kind, mode_name(mode), mappings, descriptions, value, false)
end

function M.footer(kind, mode, mappings, options, value)
    local action_help = get_action_help(options)
    if
        action_help == false
        or action_help.enabled == false
        or action_help.footer == false
    then
        return nil
    end

    mode = mode_name(mode or current_mode())
    local descriptions = type(action_help) == "table" and action_help.descriptions or nil
    local items = entries(kind, mode, mappings, descriptions, value, true)
    local parts = {}
    for _, item in ipairs(items) do
        local text = item.key .. " " .. item.short
        if value and not item.available then
            text = text .. " unavailable"
        end
        parts[#parts + 1] = text
    end
    local key = help_key(options)
    if key and not (mappings and mappings[mode] and mappings[mode][key] ~= nil) then
        parts[#parts + 1] = key .. " actions"
    end

    local full = table.concat(parts, "   ")
    local max_width = math.max(1, (vim.o.columns or 80) - 4)
    if display_width(full) <= max_width then
        return full
    end

    local compact_parts = {}
    for _, item in ipairs(items) do
        local label = item.short
            :gsub("switch/focus", "focus")
            :gsub("switch", "sw")
            :gsub("expand/collapse", "expand")
            :gsub("rename", "ren")
            :gsub("unload", "unld")
            :gsub("delete", "del")
        local text = item.key .. " " .. label
        if value and not item.available then
            text = item.key .. " unavailable"
        end
        compact_parts[#compact_parts + 1] = text
    end
    if key and not (mappings and mappings[mode] and mappings[mode][key] ~= nil) then
        compact_parts[#compact_parts + 1] = key .. " actions"
    end
    local compact = table.concat(compact_parts, "  ")
    if display_width(compact) > max_width then
        local keys = {}
        for _, item in ipairs(items) do
            keys[#keys + 1] = item.key
        end
        if key and not (mappings and mappings[mode] and mappings[mode][key] ~= nil) then
            keys[#keys + 1] = key .. " actions"
        end
        compact = table.concat(keys, "  ")
    end
    return shorten(compact, max_width)
end

function M.lines(kind, mappings, options, value)
    local action_help = get_action_help(options)
    local custom = type(action_help) == "table" and action_help.descriptions or nil
    local lines = { "Session actions" }
    local insert = entries(kind, "i", mappings, custom, value, false)
    local normal = entries(kind, "n", mappings, custom, value, false)

    local function same(left, right)
        if #left ~= #right then
            return false
        end
        for index, item in ipairs(left) do
            local other = right[index]
            if
                item.key ~= other.key
                or item.action ~= other.action
                or item.label ~= other.label
            then
                return false
            end
        end
        return true
    end

    local function append(mode, mode_entries)
        if #mode_entries == 0 then
            return
        end
        if not same(insert, normal) then
            lines[#lines + 1] = mode == "i" and "  Insert mode" or "  Normal mode"
        end
        for _, item in ipairs(mode_entries) do
            lines[#lines + 1] = "    " .. item.key .. "  " .. item.label
        end
    end

    append("i", insert)
    if not same(insert, normal) then
        append("n", normal)
    end
    if #lines == 1 then
        lines[#lines + 1] = "  No actions available for this row"
    end
    return lines
end

local open_popups = {}

local function close_popup(prompt_bufnr)
    local popup = open_popups[prompt_bufnr]
    if not popup then
        return
    end
    open_popups[prompt_bufnr] = nil
    if popup.win and vim.api.nvim_win_is_valid(popup.win) then
        vim.api.nvim_win_close(popup.win, true)
    end
    if popup.buf and vim.api.nvim_buf_is_valid(popup.buf) then
        vim.api.nvim_buf_delete(popup.buf, { force = true })
    end
    if popup.origin and vim.api.nvim_win_is_valid(popup.origin) then
        pcall(vim.api.nvim_set_current_win, popup.origin)
    end
end

function M.show(prompt_bufnr, kind, mappings, options)
    close_popup(prompt_bufnr)
    local value = selected_value()
    local lines = M.lines(kind, mappings, options, value)
    local width = 0
    for _, line in ipairs(lines) do
        width = math.max(width, display_width(line))
    end
    width = math.min(width + 2, math.max(20, (vim.o.columns or 80) - 4))
    local height = math.min(#lines + 2, math.max(3, (vim.o.lines or 24) - 4))
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].modifiable = false
    local origin = vim.api.nvim_get_current_win()
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = math.max(0, math.floor(((vim.o.lines or 24) - height) / 2)),
        col = math.max(0, math.floor(((vim.o.columns or 80) - width) / 2)),
        width = width,
        height = height,
        border = "rounded",
        style = "minimal",
    })
    open_popups[prompt_bufnr] = { buf = buf, win = win, origin = origin }
    vim.keymap.set({ "n", "i" }, "q", function()
        close_popup(prompt_bufnr)
    end, { buffer = buf, silent = true, nowait = true })
    vim.keymap.set({ "n", "i" }, "<Esc>", function()
        close_popup(prompt_bufnr)
    end, { buffer = buf, silent = true, nowait = true })
    vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
        buffer = prompt_bufnr,
        once = true,
        callback = function()
            close_popup(prompt_bufnr)
        end,
    })
end

function M.help_key(options)
    return help_key(options)
end

return M
