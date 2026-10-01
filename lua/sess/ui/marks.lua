local api = require("sess.api")
local log = require("sess.log")
local mark_rules = require("sess.mark")
local window = require("sess.ui.window")

local M = {}

local active_popup
local next_group = 0

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

local function read_key()
    local ok, key = pcall(vim.fn.getcharstr)
    if not ok or type(key) ~= "string" or key == "" then
        return nil
    end
    return key
end

local function read_mark(value)
    value = value == nil and read_key() or value
    if value == nil or value == "\27" then
        return nil
    end
    local mark, err = M.parse(value)
    if not mark then
        log.error(err)
    end
    return mark
end

local function read_popup_mark()
    local value = read_key()
    if value == nil or value == "\27" then
        return nil
    end
    local valid, err = mark_rules.validate(value)
    if not valid then
        log.error(err)
        return nil
    end
    return value
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

local function keycode(value)
    return vim.api.nvim_replace_termcodes(value, true, false, true)
end

function M.setup_keymap(keymap)
    local mappings = {
        {
            lhs = keymap.prefix,
            callback = M.goto_mark,
            desc = "Sess: goto mark",
        },
        {
            lhs = keymap.prefix .. keymap.set_mark,
            callback = M.set_mark,
            desc = "Sess: set mark",
        },
        {
            lhs = keymap.prefix .. keymap.edit_marks,
            callback = M.edit_marks,
            desc = "Sess: edit marks",
        },
    }

    local ok, err = pcall(function()
        for _, mapping in ipairs(mappings) do
            vim.keymap.set("n", mapping.lhs, mapping.callback, {
                desc = mapping.desc,
                noremap = true,
                silent = true,
            })
        end
    end)
    if not ok then
        return false, "Failed to install mark keymaps: " .. tostring(err)
    end
    return true
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

local function selected_mark(popup)
    local row = current_row(popup)
    return row and popup.rows[row], row
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
    local called, ok, err, item, diagnostics = pcall(operation, ...)
    if not called then
        log.error(tostring(ok))
        return false, nil, {}
    end
    if not ok then
        log.error(err)
        log.diagnostics(diagnostics)
        return false, item, diagnostics or {}
    end
    log.diagnostics(diagnostics)
    return true, item, diagnostics or {}
end

local function resolve_mark(mark)
    local ok, item = run_logged_operation(api.session.get_by_mark, mark)
    return ok and item or nil
end

local function select_mark(mark)
    local item = resolve_mark(mark)
    if not item then
        close_popup(true)
        return false
    end
    if not close_popup(true) then
        return false
    end
    return run_logged_operation(api.session.load, "@" .. mark)
end

local function select_current(popup)
    local mark = selected_mark(popup)
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
        pcall(vim.api.nvim_set_option_value, "modifiable", false, { buf = buf })
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
        lines[#lines + 1] = truncate(mark .. "  " .. name, width)
        rows[#rows + 1] = entry.mark
    end

    if #lines == 0 then
        lines = { "No marks assigned", "Use :Sess mark @x to assign one" }
    end
    return lines, rows
end

local function list_entries()
    local called, ok, err, entries, diagnostics = pcall(api.session.list_marks)
    if not called then
        return nil, tostring(ok)
    end
    if not ok then
        return nil, err
    end
    return entries or {}, nil, diagnostics or {}
end

local function find_entry(entries, mark)
    for _, entry in ipairs(entries) do
        if entry.mark == mark then
            return entry
        end
    end
end

local function entry_owner(entry)
    return entry.session and entry.session.metadata.name or (entry.id .. " (stale)")
end

local function refresh(popup, preferred_mark)
    if not popup_valid(popup) then
        return false
    end
    local old_mark, old_row = selected_mark(popup)
    local entries, err, diagnostics = list_entries()
    if not entries then
        log.error(err)
        return false
    end
    log.diagnostics(diagnostics)

    local lines, rows = render(entries, popup.window.geometry.width)
    local rendered, render_err = set_lines(popup, lines)
    if not rendered then
        log.error("Failed to render mark popup: " .. render_err)
        return false
    end
    popup.rows = rows

    local mark = preferred_mark or old_mark
    local row
    if mark then
        for index, value in ipairs(rows) do
            if value == mark then
                row = index
                break
            end
        end
    end
    row = row or math.min(old_row or 1, math.max(1, #rows))
    if window.is_valid(popup.window) then
        pcall(vim.api.nvim_win_set_cursor, popup.window.win, { row, 0 })
    end
    return true
end

local function confirm(popup, question)
    popup.interacting = true
    local called, choice = pcall(vim.fn.confirm, question, "&Yes\n&No", 2)
    popup.interacting = false
    if not called then
        log.error(tostring(choice))
        return false
    end
    return choice == 1
end

local function install_mappings(popup)
    local keymap = popup.window.options.keymap
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
    map(keymap.load_prefix, function()
        if not popup_active(popup) then
            return
        end
        local mark = read_popup_mark()
        if mark then
            select_mark(mark)
        end
    end)
    map(keymap.delete, function()
        local mark = selected_mark(popup)
        if not mark or not popup_active(popup) then
            return
        end
        local entries, err, diagnostics = list_entries()
        if not entries then
            log.error(err)
            return
        end
        log.diagnostics(diagnostics)
        local entry = find_entry(entries, mark)
        if not entry then
            log.error("mark not found: @" .. mark)
            refresh(popup)
            return
        end
        if not confirm(popup, "Clear mark @" .. mark .. " on " .. entry_owner(entry) .. "?") then
            return
        end
        local ok, _, _, clear_diagnostics = run_logged_operation(
            api.session.clear_mark,
            mark,
            { expected_id = entry.id }
        )
        if ok then
            popup.undo = {
                changes = { { mark = mark, expected = nil, value = entry.id } },
            }
            refresh(popup)
            log.diagnostics(clear_diagnostics)
        end
    end)
    map(keymap.undo, function()
        if not popup_active(popup) or not popup.undo then
            return
        end
        local undo = popup.undo
        local ok = run_logged_operation(api.session.restore_marks, undo.changes)
        if ok then
            popup.undo = nil
            refresh(popup)
        end
    end)
    map(keymap.change_mark, function()
        local old_mark = selected_mark(popup)
        if not old_mark or not popup_active(popup) then
            return
        end
        local entries, err, diagnostics = list_entries()
        if not entries then
            log.error(err)
            return
        end
        log.diagnostics(diagnostics)
        local source = find_entry(entries, old_mark)
        if not source then
            log.error("mark not found: @" .. old_mark)
            refresh(popup)
            return
        end

        local new_mark = read_popup_mark()
        if not new_mark or new_mark == old_mark then
            return
        end
        local destination = find_entry(entries, new_mark)
        if destination then
            if
                not confirm(
                    popup,
                    "Replace mark @" .. new_mark .. " on " .. entry_owner(destination) .. "?"
                )
            then
                return
            end
        end

        local ok = run_logged_operation(api.session.move_mark, old_mark, new_mark, {
            replace = destination ~= nil,
            expected_id = source.id,
            check_destination = true,
            expected_destination = destination and destination.id or nil,
        })
        if ok then
            popup.undo = {
                changes = {
                    { mark = old_mark, expected = nil, value = source.id },
                    {
                        mark = new_mark,
                        expected = source.id,
                        value = destination and destination.id or nil,
                    },
                },
            }
            refresh(popup, new_mark)
        end
    end)
    map(keymap.rename, function()
        local mark = selected_mark(popup)
        if not mark or not popup_active(popup) then
            return
        end
        local item = resolve_mark(mark)
        if not item then
            return
        end
        popup.interacting = true
        local called, input_err = pcall(vim.ui.input, {
            prompt = "Rename session: ",
            default = item.metadata.name,
        }, function(value)
            popup.interacting = false
            if value == nil or vim.trim(value) == "" or not popup_active(popup) then
                return
            end
            local ok = run_logged_operation(api.session.rename, item.id, value)
            if ok then
                refresh(popup, mark)
            end
        end)
        if not called then
            popup.interacting = false
            log.error(tostring(input_err))
        end
    end)
end

local function install_autocmds(popup)
    next_group = next_group + 1
    popup.group = vim.api.nvim_create_augroup("SessNvimMarkWindow" .. next_group, { clear = true })
    vim.api.nvim_create_autocmd("WinLeave", {
        group = popup.group,
        callback = function(event)
            if not popup_active(popup) or popup.interacting then
                return
            end
            if event.win == popup.window.win then
                close_popup(true)
            end
        end,
    })
    vim.api.nvim_create_autocmd("TabLeave", {
        group = popup.group,
        callback = function()
            if not popup_active(popup) or popup.interacting then
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

local function open_popup(focus)
    if popup_valid(active_popup) then
        if focus then
            vim.api.nvim_set_current_win(active_popup.window.win)
        end
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
    local entries, err, diagnostics = list_entries()
    if not entries then
        log.error(err)
        return false
    end
    log.diagnostics(diagnostics)

    local options = api.opts.get().mark_window
    local popup_window, open_err = window.open(options, focus)
    if not popup_window then
        log.error(open_err)
        return false
    end
    local popup = {
        window = popup_window,
        origin_win = origin_win,
        origin_tab = origin_tab,
        rows = {},
    }
    active_popup = popup
    local lines, rows = render(entries, popup_window.geometry.width)
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

function M.edit_marks()
    return open_popup(true)
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
        local keymap = api.opts.get().keymap
        local edit_key = keycode(keymap.edit_marks)
        local set_mark_key = keycode(keymap.set_mark)
        if not open_popup(false) then
            return false
        end
        vim.cmd("redraw")

        local key = read_key()
        if key == nil or key == "\27" then
            close_popup(true)
            return false
        end
        if key == edit_key then
            return open_popup(true)
        end
        if key == set_mark_key then
            close_popup(true)
            return M.set_mark()
        end
        local mark, err = M.parse(key)
        if not mark then
            log.error(err)
            close_popup(true)
            return false
        end
        value = mark
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
