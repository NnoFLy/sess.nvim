local api = require("sess.api")
local log = require("sess.log")
local mark_rules = require("sess.mark")
local window = require("sess.ui.window")

local M = {}

local active_popup
local next_group = 0
local mark_keys = {}

for code = string.byte("a"), string.byte("z") do
    mark_keys[#mark_keys + 1] = string.char(code)
end
for code = string.byte("0"), string.byte("9") do
    mark_keys[#mark_keys + 1] = string.char(code)
end

-- Command syntax requires @; Lua navigation and picker input may omit it.
function M.parse(value, require_prefix)
    if type(value) ~= "string" then
        return nil, "mark is required"
    end
    if value:sub(1, 1) == "@" then
        value = value:sub(2)
    elseif require_prefix then
        return nil, "mark must use @ followed by one lowercase ASCII letter or digit"
    end
    local valid, err = mark_rules.validate(value)
    return valid and value or nil, err
end

-- Confirmation belongs here, never in the prompt-free lifecycle.
function M.assign(target, mark)
    local valid, validation_err = mark_rules.validate(mark)
    if not valid then
        return false, validation_err
    end
    local ok, err, entries, diagnostics = api.session.list_marks()
    if not ok then
        return false, err
    end
    local replace = false
    for _, entry in ipairs(entries) do
        if entry.mark == mark then
            local owner = entry.session and entry.session.metadata.name or (entry.id .. " (stale)")
            if
                vim.fn.confirm("Replace mark @" .. mark .. " on " .. owner .. "?", "&Yes\n&No", 2)
                ~= 1
            then
                return false, "mark cancelled"
            end
            replace = true
            break
        end
    end
    local assigned, assign_err, item, result_diagnostics =
        api.session.set_mark(target, mark, { replace = replace })
    if assigned then
        vim.list_extend(result_diagnostics, diagnostics or {})
    end
    return assigned, assign_err, item, result_diagnostics
end

function M.report(ok, err, diagnostics)
    if ok then
        log.diagnostics(diagnostics)
    elseif err == "mark cancelled" then
        log.info("Mark cancelled")
    else
        log.error(err)
    end
    return ok
end

local function read_mark(value)
    if value == nil then
        local ok, key = pcall(vim.fn.getcharstr)
        if not ok then
            return nil
        end
        value = key
    end
    if value == "\27" then
        return nil
    end
    local mark, err = M.parse(value)
    if not mark then
        log.error(err)
    end
    return mark
end

local function sanitize(value)
    return tostring(value or ""):gsub("[%c]", " ")
end

local function truncate(value, width)
    if vim.fn.strdisplaywidth(value) <= width then
        return value
    end
    if width <= 1 then
        return " "
    end
    local result = ""
    local count = vim.fn.strchars(value)
    for index = 1, count do
        local candidate = vim.fn.strcharpart(value, 0, index)
        if vim.fn.strdisplaywidth(candidate .. "…") > width then
            break
        end
        result = candidate
    end
    return result .. "…"
end

local function popup_active(popup)
    return popup ~= nil and active_popup == popup and not popup.closing
end

local function popup_valid(popup)
    return popup_active(popup) and window.is_valid(popup.window)
end

local function delete_autocmd_group(popup)
    if popup and popup.group then
        pcall(vim.api.nvim_del_augroup_by_id, popup.group)
        popup.group = nil
    end
end

local function restore_origin_window(popup)
    if not popup or not vim.api.nvim_tabpage_is_valid(popup.origin_tab) then
        return
    end
    if vim.api.nvim_get_current_tabpage() ~= popup.origin_tab then
        return
    end
    if vim.api.nvim_win_is_valid(popup.origin_win) then
        pcall(vim.api.nvim_set_current_win, popup.origin_win)
    end
end

local function close_popup(restore_focus)
    local popup = active_popup
    if not popup then
        return true
    end

    active_popup = nil
    popup.closing = true
    delete_autocmd_group(popup)
    local ok, err = window.close(popup.window)
    if not ok then
        log.error("Failed to close mark popup: " .. tostring(err))
        return false
    end
    if restore_focus then
        restore_origin_window(popup)
    end
    return true
end

local function current_row(popup)
    if not window.is_valid(popup.window) then
        return nil
    end
    return vim.api.nvim_win_get_cursor(popup.window.win)[1]
end

local function move(popup, amount)
    local row = current_row(popup)
    if not row or #popup.rows == 0 then
        return
    end
    local target = math.max(1, math.min(#popup.rows, row + amount))
    vim.api.nvim_win_set_cursor(popup.window.win, { target, 0 })
end

local function run_logged_operation(operation, ...)
    local called, ok, err, _, diagnostics = pcall(operation, ...)
    if not called then
        log.error(tostring(ok))
        return false
    end
    if not ok then
        log.error(err)
        return false
    end
    log.diagnostics(diagnostics)
    return true
end

local function select_mark(mark)
    if not active_popup or not close_popup(true) then
        return
    end
    if not run_logged_operation(api.session.get_by_mark, mark) then
        return
    end
    run_logged_operation(api.session.load, "@" .. mark)
end

local function select_current(popup)
    local row = current_row(popup)
    local mark = row and popup.rows[row]
    if mark then
        select_mark(mark)
    end
end

local function set_lines(popup, lines)
    local buf = popup.window.buf
    local ok, err = pcall(function()
        vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
    end)
    if not ok then
        return false, tostring(err)
    end
    return true
end

local function render(entries, width)
    local lines, rows = {}, {}
    for _, entry in ipairs(entries) do
        local name = entry.session and entry.session.metadata.name or entry.id
        name = sanitize(name)
        if entry.stale then
            name = name .. " (unavailable)"
        end
        local mark = sanitize(entry.mark)
        local prefix = mark .. "  "
        lines[#lines + 1] = truncate(prefix .. name, width)
        rows[#rows + 1] = entry.mark
    end

    if #lines == 0 then
        lines = { "No marks assigned", "Use :Sess mark @x to assign one" }
    end
    return lines, rows
end

local function install_mappings(popup)
    local opts = { buffer = popup.window.buf, noremap = true, silent = true, nowait = true }
    local function map(lhs, callback)
        vim.keymap.set("n", lhs, callback, opts)
    end

    map("<Up>", function()
        move(popup, -1)
    end)
    map("<Down>", function()
        move(popup, 1)
    end)
    map("<CR>", function()
        select_current(popup)
    end)
    map("<Esc>", function()
        close_popup(true)
    end)
    map("<C-c>", function()
        close_popup(true)
    end)

    local assigned = {}
    for _, mark in ipairs(popup.rows) do
        assigned[mark] = true
    end
    for _, key in ipairs(mark_keys) do
        if assigned[key] then
            map(key, function()
                select_mark(key)
            end)
        else
            -- Every valid mark key is consumed locally. In particular, q/j/k
            -- remain available as ordinary mark names without being commands.
            map(key, function() end)
        end
    end
end

local function install_autocmds(popup)
    next_group = next_group + 1
    popup.group = vim.api.nvim_create_augroup("SessNvimMarkWindow" .. next_group, { clear = true })
    vim.api.nvim_create_autocmd("WinLeave", {
        group = popup.group,
        callback = function()
            if not popup_active(popup) then
                return
            end
            if vim.api.nvim_get_current_win() == popup.window.win then
                close_popup(true)
            end
        end,
    })
    vim.api.nvim_create_autocmd("TabLeave", {
        group = popup.group,
        callback = function()
            if not popup_active(popup) then
                return
            end
            if vim.tbl_contains(vim.api.nvim_tabpage_list_wins(0), popup.window.win) then
                close_popup(false)
            end
        end,
    })
    vim.api.nvim_create_autocmd("VimResized", {
        group = popup.group,
        callback = function()
            if not popup_valid(popup) then
                return
            end
            local ok, err = window.update(popup.window)
            if not ok then
                log.error("Failed to resize mark popup: " .. tostring(err))
                close_popup(true)
            end
        end,
    })
    vim.api.nvim_create_autocmd("BufWipeout", {
        group = popup.group,
        buffer = popup.window.buf,
        callback = function()
            if active_popup == popup then
                active_popup = nil
                delete_autocmd_group(popup)
            end
        end,
    })
end

local function open_popup()
    if popup_valid(active_popup) then
        vim.api.nvim_set_current_win(active_popup.window.win)
        return true
    end
    if active_popup then
        local stale_popup = active_popup
        active_popup = nil
        delete_autocmd_group(stale_popup)
        local cleaned, cleanup_err = window.close(stale_popup.window)
        if not cleaned then
            log.error("Failed to clean up mark popup: " .. tostring(cleanup_err))
        end
    end

    local origin_win = vim.api.nvim_get_current_win()
    local origin_tab = vim.api.nvim_get_current_tabpage()
    local called, ok, err, entries, diagnostics = pcall(api.session.list_marks)
    if not called then
        log.error(tostring(ok))
        return false
    end
    if not ok then
        log.error(err)
        return false
    end
    log.diagnostics(diagnostics)
    entries = entries or {}
    table.sort(entries, function(left, right)
        return left.mark < right.mark
    end)

    local options = api.opts.get().mark_window
    local popup_window, open_err = window.open(options)
    if not popup_window then
        log.error(open_err)
        return false
    end
    local popup = {
        window = popup_window,
        origin_win = origin_win,
        origin_tab = origin_tab,
    }
    active_popup = popup
    local width = popup_window.geometry.width
    local lines, rows = render(entries, width)
    popup.rows = rows
    local rendered, render_err = set_lines(popup, lines)
    if not rendered then
        close_popup(false)
        log.error("Failed to render mark popup: " .. render_err)
        return false
    end
    local installed, install_err = pcall(function()
        install_mappings(popup)
        install_autocmds(popup)
    end)
    if not installed then
        close_popup(false)
        log.error("Failed to initialize mark popup: " .. tostring(install_err))
        return false
    end
    return true
end

function M.set_mark(value)
    local mark = read_mark(value)
    if not mark then
        return false
    end
    local ok, assigned, assign_err, _, diagnostics = pcall(M.assign, nil, mark)
    if not ok then
        log.error(tostring(assigned))
        return false
    end
    return M.report(assigned, assign_err, diagnostics)
end

function M.goto_mark(value)
    if value == nil then
        return open_popup()
    end

    local mark, err = M.parse(value)
    if not mark then
        log.error(err)
        return false
    end
    if not close_popup(true) then
        return false
    end

    local called, ok, load_err, _, diagnostics = pcall(api.session.load, "@" .. mark)
    if not called then
        log.error(tostring(ok))
        return false
    end
    if ok then
        return M.report(ok, load_err, diagnostics)
    end

    if load_err ~= "mark not found: @" .. mark then
        return M.report(false, load_err, diagnostics)
    end

    local assign_called, assigned, assign_err, _, assign_diagnostics = pcall(M.assign, nil, mark)
    if not assign_called then
        log.error(tostring(assigned))
        return false
    end
    if not assigned then
        return M.report(false, assign_err, assign_diagnostics)
    end

    log.info("Created mark @" .. mark .. " on current session")
    return M.report(true, nil, assign_diagnostics)
end

return M
