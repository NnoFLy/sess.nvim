local api = require("sess.api")
local editor = require("sess.editor")
local icons = require("sess.ui.icons")
local log = require("sess.log")
local rows = require("sess.ui.rows")
local display = require("sess.ui.display")
local search = require("sess.ui.search")
local marks = require("sess.ui.marks")
local help = require("sess.ui.sidebar_help")
local tabline = require("sess.ui.tabline")

local M = {}

local state = {
    options = {
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
    open = false,
    buf = nil,
    win = nil,
    tab = nil,
    snapshot = nil,
    rows = {},
    selected_key = nil,
    expanded = {},
    row_lines = {},
    timer = nil,
    cancel_task = nil,
    refreshing = false,
    pending_action = nil,
    instance = nil,
    refresh_token = nil,
    sort = "default",
    rendering = false,
    window_lost = false,
    closing_window = false,
    cleanup_in_progress = false,
    operation = nil,
    resizing = false,
    buffer_heading_visible = true,
}

local namespace = vim.api.nvim_create_namespace("sess-sidebar")
local sidebar_group = vim.api.nvim_create_augroup("sess-sidebar", { clear = false })
local sidebar_buffer_name = "Sess Sidebar"

-- Sidebar rendering must remain usable when Telescope is not installed. Keep
-- these links defaulted so users can override them without losing semantic
-- status distinctions.
local sidebar_highlights = {
    SessSidebarCurrent = "Identifier",
    SessSidebarActive = "Identifier",
    SessSidebarName = "Normal",
    SessSidebarPath = "Comment",
    SessSidebarMark = "Number",
    SessSidebarMetadata = "Comment",
    SessSidebarStale = "DiagnosticHint",
    SessSidebarAgent = "Identifier",
    SessSidebarFocused = "IncSearch",
    SessSidebarWorking = "Identifier",
    SessSidebarIdle = "Comment",
    SessSidebarBlocked = "DiagnosticWarn",
    SessSidebarDone = "DiagnosticOk",
    SessSidebarUnknown = "DiagnosticInfo",
    SessSidebarTitle = "Title",
    SessSidebarFooter = "NonText",
}

for group, link in pairs(sidebar_highlights) do
    vim.api.nvim_set_hl(0, group, { default = true, link = link })
end

local function valid_buffer(buf)
    return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function valid_window(win)
    return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

local function close_window(win)
    local called, result = pcall(vim.api.nvim_win_close, win, true)
    if not called then
        return false, result
    end
    if result == false then
        return false, "window close returned false"
    end
    return true
end

local function close_owned_window(win)
    if state.cleanup_in_progress then
        return false, "sidebar cleanup already in progress"
    end
    state.cleanup_in_progress = true
    state.closing_window = true
    local closed, close_err = close_window(win)
    state.closing_window = false
    state.cleanup_in_progress = false
    return closed, close_err
end

local function run_operation(name, callback)
    if state.operation then
        return false, "sidebar " .. tostring(state.operation) .. " operation already in progress"
    end
    state.operation = name
    local called, result, err = xpcall(callback, debug.traceback)
    state.operation = nil
    if not called then
        return false, tostring(result)
    end
    return result, err
end

local function notify_diagnostics(values)
    for _, diagnostic in ipairs(values or {}) do
        if type(diagnostic) == "string" and diagnostic ~= "" then
            log.warn("sidebar: " .. diagnostic)
        end
    end
end

local function set_transient(buf)
    vim.b[buf].sess_transient_ui = true
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "hide"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = true
end

local function sync_selection()
    if state.rendering or not state.open or not valid_window(state.win) then
        return
    end
    local ok, cursor = pcall(vim.api.nvim_win_get_cursor, state.win)
    if not ok then
        return
    end
    for index, line in ipairs(state.row_lines) do
        if line == cursor[1] and state.rows[index] then
            state.selected_key = state.rows[index].key
            return
        end
    end
end

local function get_buffer()
    if not valid_buffer(state.buf) then
        state.buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_name(state.buf, sidebar_buffer_name)
        set_transient(state.buf)
        vim.api.nvim_create_autocmd("CursorMoved", {
            group = sidebar_group,
            buffer = state.buf,
            callback = sync_selection,
        })
    end
    return state.buf
end

local function remove_timer()
    if state.timer then
        state.timer:stop()
        state.timer:close()
        state.timer = nil
    end
end

local function cancel_refresh()
    if state.cancel_task then
        state.cancel_task()
        state.cancel_task = nil
    end
    state.refreshing = false
    state.refresh_token = nil
end

local function stop_polling()
    remove_timer()
    cancel_refresh()
end

local function start_polling()
    remove_timer()
    if not state.open then
        return
    end
    local timer = vim.uv and vim.uv.new_timer() or vim.loop.new_timer()
    if not timer then
        return
    end
    state.timer = timer
    timer:start(state.options.refresh_interval, state.options.refresh_interval, function()
        vim.schedule(function()
            if state.open and state.timer == timer then
                M.refresh()
            end
        end)
    end)
end

local function row_options(width)
    return {
        available_width = width,
        active = true,
        symbols = icons.for_display(),
        highlights = {
            current = "SessSidebarCurrent",
            active = "SessSidebarActive",
            name = "SessSidebarName",
            cwd = "SessSidebarPath",
            mark = "SessSidebarMark",
            metadata = "SessSidebarMetadata",
            stale = "SessSidebarStale",
            agent = "SessSidebarAgent",
            focused = "SessSidebarFocused",
            working = "SessSidebarWorking",
            idle = "SessSidebarIdle",
            blocked = "SessSidebarBlocked",
            done = "SessSidebarDone",
            unknown = "SessSidebarUnknown",
        },
        show_metadata = false,
        show_pinned = true,
        show_agent_summary = true,
        sort = state.sort,
    }
end

local function initial_expansion(snapshot)
    local result = {}
    local mode = state.options.active_expand
    result[rows.key("background_terminals", "")] = mode == "all"
    for _, session in ipairs(snapshot.sessions or {}) do
        local key = rows.session_key(session.id)
        result[key] = mode == "all" or (mode == "current" and snapshot.current_id == session.id)
    end
    return result
end

local function selected_index(list)
    if not state.selected_key then
        return nil
    end
    for index, row in ipairs(list) do
        if row.key == state.selected_key then
            return index
        end
    end
end

local function choose_selection(candidate)
    local index = selected_index(candidate)
    if index then
        return candidate[index].key
    end
    local old_index
    if state.selected_key then
        local old = state.selected_key
        local parent
        for current, row in ipairs(state.rows) do
            if row.key == old then
                old_index, parent = current, row.parent_key
                if row.kind == "terminal" then
                    for _, header in ipairs(candidate) do
                        if vim.tbl_contains(header.terminal_ids or {}, row.terminal_id) then
                            return header.key
                        end
                    end
                end
                break
            end
        end
        if parent then
            for _, row in ipairs(candidate) do
                if row.key == parent then
                    return row.key
                end
            end
        end
    end

    -- Keep the selection near the row that disappeared before falling back to
    -- the first actionable row. This avoids jumping to the top on refresh.
    if old_index then
        local nearest, nearest_distance, nearest_index
        for current, row in ipairs(candidate) do
            if row.kind ~= "placeholder" then
                local distance = math.abs(current - old_index)
                if not nearest_distance or distance < nearest_distance then
                    nearest, nearest_distance, nearest_index = row.key, distance, current
                elseif distance == nearest_distance and current < nearest_index then
                    nearest, nearest_index = row.key, current
                end
            end
        end
        if nearest then
            return nearest
        end
    end
    for _, row in ipairs(candidate) do
        if row.kind ~= "placeholder" then
            return row.key
        end
    end
end

local function lines_for(candidate)
    local width = math.max(1, vim.api.nvim_win_get_width(state.win))
    local separator = string.rep("─", width)
    local lines = {}
    if not tabline.heading_visible() then
        lines[#lines + 1] = display.truncate_end("ACTIVE SESSIONS", width)
    end
    lines[#lines + 1] = separator
    local row_lines = {}
    for index, row in ipairs(candidate) do
        row_lines[#row_lines + 1] = #lines + 1
        lines[#lines + 1] = row.display or ""
    end
    lines[#lines + 1] = separator
    lines[#lines + 1] = display.truncate_end("sort: " .. state.sort, width)
    lines[#lines + 1] = ""
    lines[#lines + 1] = display.truncate_end("? - Help", width)
    return lines, row_lines
end

local function apply_highlights(line_number, parts)
    local byte = 0
    for _, part in ipairs(parts or {}) do
        local text = part.text or ""
        if part.highlight and text ~= "" then
            vim.api.nvim_buf_add_highlight(
                state.buf,
                namespace,
                part.highlight,
                line_number,
                byte,
                byte + #text
            )
        end
        byte = byte + #text
    end
end

local function saved_highlights()
    local ok, marks = pcall(vim.api.nvim_buf_get_extmarks, state.buf, namespace, 0, -1, {
        details = true,
    })
    if not ok then
        return false, marks
    end
    return true, marks
end

local function restore_highlights(marks)
    for _, mark in ipairs(marks or {}) do
        local details = mark[4] or {}
        local highlight = details.hl_group
        if highlight then
            local end_col = details.end_col or mark[3]
            vim.api.nvim_buf_add_highlight(
                state.buf,
                namespace,
                highlight,
                mark[2],
                mark[3],
                end_col
            )
        end
    end
end

local function render(candidate, selected, force_selection)
    if not valid_buffer(state.buf) or not valid_window(state.win) then
        return false, "sidebar window is unavailable"
    end
    local lines, row_lines = lines_for(candidate)
    local old_lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)
    local old_rows = state.row_lines
    local saved_view
    if not force_selection and #old_rows > 0 then
        local cursor_line = vim.api.nvim_win_get_cursor(state.win)[1]
        -- Keep free cursor movement outside the session/agent rows on refresh.
        if not vim.list_contains(old_rows, cursor_line) then
            saved_view = vim.api.nvim_win_call(state.win, vim.fn.winsaveview)
            local buffer_heading_visible = not tabline.heading_visible()
            if state.buffer_heading_visible ~= buffer_heading_visible then
                local delta = buffer_heading_visible and 1 or -1
                saved_view.lnum = math.max(1, saved_view.lnum + delta)
                saved_view.topline = math.max(1, saved_view.topline + delta)
            end
        end
    end
    local highlights_ok, old_highlights = saved_highlights()
    if not highlights_ok then
        return false, tostring(old_highlights)
    end
    state.rendering = true
    local ok, err = pcall(function()
        vim.bo[state.buf].modifiable = true
        vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
        vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
        if not tabline.heading_visible() then
            apply_highlights(0, { { text = lines[1], highlight = "SessSidebarTitle" } })
        end
        for index, row in ipairs(candidate) do
            apply_highlights(row_lines[index] - 1, row.display_parts)
        end
        for line = #lines - 2, #lines - 1 do
            apply_highlights(line, { { text = lines[line], highlight = "SessSidebarFooter" } })
        end
        vim.bo[state.buf].modifiable = false
    end)
    if not ok then
        pcall(function()
            vim.bo[state.buf].modifiable = true
            vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, old_lines)
            vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
            restore_highlights(old_highlights)
            vim.bo[state.buf].modifiable = false
            state.row_lines = old_rows
        end)
        state.rendering = false
        return false, tostring(err)
    end
    state.row_lines = row_lines
    state.buffer_heading_visible = not tabline.heading_visible()
    local cursor = 1
    if selected then
        for index, row in ipairs(candidate) do
            if row.key == selected then
                cursor = row_lines[index]
                break
            end
        end
    end
    if saved_view then
        pcall(vim.api.nvim_win_call, state.win, function()
            vim.fn.winrestview(saved_view)
        end)
    else
        pcall(vim.api.nvim_win_set_cursor, state.win, { cursor, 0 })
    end
    state.rendering = false
    return true
end

local function build(snapshot)
    if type(snapshot) ~= "table" then
        return nil, "active snapshot is malformed"
    end
    local width = vim.api.nvim_win_get_width(state.win)
    local options = row_options(width)
    -- Apply defaults to newly observed sessions, preserving explicit false values.
    options.expanded = vim.tbl_extend("keep", state.expanded, initial_expansion(snapshot))
    local ok, candidate, metadata = pcall(rows.build_active, snapshot, options)
    if not ok then
        return nil, tostring(candidate)
    end
    if type(candidate) ~= "table" or type(metadata) ~= "table" then
        return nil, "active rows are malformed"
    end
    notify_diagnostics(metadata.diagnostics)
    return candidate
end

local function commit(snapshot, candidate)
    sync_selection()
    local selected = choose_selection(candidate)
    local ok, err = render(candidate, selected)
    if not ok then
        return false, err
    end
    state.snapshot = vim.deepcopy(snapshot)
    state.rows = vim.deepcopy(candidate)
    for _, row in ipairs(candidate) do
        if row.expandable then
            state.expanded[row.key] = row.expanded
        end
    end
    state.selected_key = selected
    return true
end

local function report_error(err)
    notify_diagnostics({ tostring(err) })
end

local function request_refresh(options)
    if not state.open or not valid_window(state.win) or state.refreshing then
        return false
    end
    state.refreshing = true
    local token, instance = {}, state.instance
    state.refresh_token = token
    local function alive()
        return state.open and state.instance == instance and state.refresh_token == token
    end
    local function done(snapshot)
        if not alive() then
            return
        end
        local called, committed, err = pcall(function()
            local candidate, build_err = build(snapshot)
            if not candidate then
                return false, build_err
            end
            if not alive() then
                return nil
            end
            return commit(snapshot, candidate)
        end)
        if alive() then
            state.refreshing = false
            state.refresh_token = nil
            state.cancel_task = nil
        end
        if not called then
            report_error(committed)
        elseif committed == false then
            report_error(err)
        end
    end
    local async_options = vim.tbl_extend("force", {
        previous_snapshot = state.snapshot,
        on_error = function(err)
            if not alive() then
                return
            end
            state.refresh_token = nil
            state.refreshing = false
            state.cancel_task = nil
            report_error(err)
        end,
    }, options or {})
    local ok, cancel_or_err = pcall(api.active.snapshot_async, done, async_options)
    if not ok then
        if alive() then
            state.refreshing = false
            state.refresh_token = nil
        end
        report_error(cancel_or_err)
        return false
    end
    if alive() then
        state.cancel_task = type(cancel_or_err) == "function" and cancel_or_err or nil
    end
    return true
end

local function content_window()
    local tab = vim.api.nvim_get_current_tabpage()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
        if win ~= state.win and valid_window(win) and not editor.is_transient_window(win) then
            return win
        end
    end
    return vim.api.nvim_get_current_win()
end

local function ensure_width()
    local requested =
        math.max(state.options.min_width, math.min(state.options.max_width, state.options.width))
    local current_width = vim.api.nvim_win_get_width(content_window())
    -- A vertical split consumes one separator column. Leave at least one
    -- usable editor column in the window that owns the split.
    local available = current_width - 2
    if available < state.options.min_width then
        return nil, "sidebar cannot fit beside the current editor split"
    end
    return math.min(requested, available)
end

local function enforce_width()
    if not valid_window(state.win) then
        return false, "sidebar window is unavailable"
    end
    local called, width, width_err = pcall(ensure_width)
    if not called then
        return false, tostring(width)
    end
    if not width then
        return false, width_err
    end
    local ok, err = pcall(vim.api.nvim_win_set_width, state.win, width)
    if not ok then
        return false, "failed to resize sidebar: " .. tostring(err)
    end
    return true
end

local function create_window()
    local width_ok, width, err = pcall(ensure_width)
    if not width_ok then
        return nil, tostring(width)
    end
    if not width then
        return nil, err
    end
    local command = state.options.position == "right" and "botright vertical "
        or "topleft vertical "
    local win
    local ok, create_err = pcall(function()
        vim.cmd(command .. tostring(width) .. "split")
        win = vim.api.nvim_get_current_win()
        vim.api.nvim_win_set_width(win, width)
        vim.api.nvim_win_set_buf(win, get_buffer())
        vim.wo[win].number = false
        vim.wo[win].relativenumber = false
        vim.wo[win].signcolumn = "no"
        vim.wo[win].foldcolumn = "0"
        vim.wo[win].wrap = false
        vim.wo[win].cursorline = true
        vim.wo[win].winfixwidth = true
        vim.wo[win].statusline = ""
    end)
    if not ok then
        if valid_window(win) then
            pcall(vim.api.nvim_win_close, win, true)
        end
        state.win, state.tab = nil, nil
        return nil, tostring(create_err)
    end
    state.win, state.tab = win, vim.api.nvim_get_current_tabpage()
    state.window_lost = false
    return win
end

local function attach_current(force, operation)
    if state.cleanup_in_progress then
        return false, "sidebar cleanup in progress"
    end
    if state.operation and state.operation ~= operation then
        return false, "sidebar " .. tostring(state.operation) .. " operation already in progress"
    end
    if state.window_lost then
        return false, "sidebar window is unavailable"
    end
    if not state.open or (editor.is_transient_ui_suspended() and not force) then
        return true
    end
    local tab = vim.api.nvim_get_current_tabpage()
    local previous_win = vim.api.nvim_get_current_win()
    if valid_window(state.win) and state.tab == tab then
        local sidebar_buf = get_buffer()
        local replaced = vim.api.nvim_win_get_buf(state.win) ~= sidebar_buf
        if replaced then
            local attached, attach_err = pcall(vim.api.nvim_win_set_buf, state.win, sidebar_buf)
            if not attached then
                return false, "failed to restore sidebar buffer: " .. tostring(attach_err)
            end
            state.window_lost = false
            if state.snapshot then
                local candidate, build_err = build(state.snapshot)
                if not candidate then
                    return false, build_err
                end
                local committed, render_err = commit(state.snapshot, candidate)
                if not committed then
                    return false, render_err
                end
            end
        end
        if not state.resizing then
            local sized, size_err = enforce_width()
            if not sized then
                return false, size_err
            end
        end
        return true
    end
    local old_win, old_tab = state.win, state.tab
    if valid_window(old_win) then
        local closed, close_err = close_owned_window(old_win)
        if not closed then
            -- Keep ownership when cleanup fails. Creating another split would
            -- leave two sidebars and make a later retry unsafe.
            return false, "failed to close previous sidebar window: " .. tostring(close_err)
        end
    end
    state.win, state.tab = nil, nil
    local win, err = create_window()
    if not win then
        state.win, state.tab = old_win, old_tab
        stop_polling()
        return false, err
    end
    if valid_window(previous_win) and previous_win ~= win then
        pcall(vim.api.nvim_set_current_win, previous_win)
    end
    if state.snapshot then
        local candidate, build_err = build(state.snapshot)
        if candidate then
            local committed, render_err = commit(state.snapshot, candidate)
            if not committed then
                report_error(render_err)
            end
        else
            report_error(build_err)
        end
    end
    if not state.resizing then
        local sized, size_err = enforce_width()
        if not sized then
            return false, size_err
        end
    end
    return true
end

-- A remembered selection is only for refresh/navigation, never an action target.
local function selected_row()
    if not state.open or not valid_window(state.win) then
        return nil
    end
    local line = vim.api.nvim_win_get_cursor(state.win)[1]
    for index, row_line in ipairs(state.row_lines) do
        local row = state.rows[index]
        if row_line == line and row.kind ~= "placeholder" then
            return row
        end
    end
end

local function busy()
    return not state.open or state.pending_action ~= nil or state.refreshing
end

local function live_session(id)
    for _, session in ipairs(api.state.active()) do
        if session.id == id then
            return session
        end
    end
    return nil, "selected session is no longer active"
end

-- The token spans prompts as well as lifecycle calls. Closing/reopening or a
-- duplicate callback can never complete an action belonging to an old view.
local function run_action(start)
    if busy() then
        return false
    end
    local token, instance = {}, state.instance
    state.pending_action = token
    local completed = false
    local function alive()
        return state.open and state.instance == instance and state.pending_action == token
    end
    local function finish(callback)
        if completed or not alive() then
            return false
        end
        completed = true
        local called, ok, err, _, diagnostics = pcall(callback or function()
            return nil
        end)
        if state.pending_action == token then
            state.pending_action = nil
        end
        if not called then
            log.error("sidebar: " .. tostring(ok))
            return false
        end
        notify_diagnostics(diagnostics)
        if ok == false then
            if err == "unload cancelled" or err == "mark cancelled" then
                log.info(err)
            else
                log.error("sidebar: " .. tostring(err))
            end
            return false
        end
        if ok and state.open and state.instance == instance then
            local attached, attach_err = attach_current()
            if not attached then
                report_error(attach_err)
            else
                M.refresh()
            end
        end
        return ok ~= false
    end
    local called, err = pcall(start, finish, alive)
    if not called then
        if state.pending_action == token then
            state.pending_action = nil
        end
        log.error("sidebar: " .. tostring(err))
        return false
    end
    return true
end

local function session_action(callback)
    local row = selected_row()
    if not row or (row.kind ~= "session" and row.kind ~= "agent") then
        return false
    end
    return run_action(function(finish, alive)
        finish(function()
            local session, err = live_session(row.session_id)
            if not session then
                return false, err
            end
            return callback(session, row, alive)
        end)
    end)
end

local function resize_sidebar()
    if not state.open then
        return false, "sidebar is closed"
    end
    if state.resizing then
        return true
    end
    state.resizing = true
    local attached, attach_err = attach_current()
    if not attached then
        state.resizing = false
        return false, attach_err
    end
    local sized, size_err = enforce_width()
    state.resizing = false
    if sized then
        return true
    end
    local closed, close_err = M.close()
    if not closed then
        return false, tostring(size_err) .. "; " .. tostring(close_err)
    end
    return false, size_err
end

local toggle_selected

local function accept()
    local row = selected_row()
    if row and row.kind == "background_terminals" then
        return not state.expanded[row.key] and toggle_selected()
    elseif row and row.kind == "terminal" then
        return run_action(function(finish, alive)
            finish(function()
                local win = content_window()
                if not valid_window(win) or editor.is_transient_window(win) then
                    return false, "no content window available for terminal focus"
                end
                vim.api.nvim_set_current_win(win)
                -- WinEnter callbacks can close/reopen this sidebar or redirect
                -- focus. Never continue an old acceptance in the replacement UI.
                if not alive() then
                    return nil
                end
                if vim.api.nvim_get_current_win() ~= win or editor.is_transient_window(win) then
                    return false, "content window changed before terminal focus"
                end
                return api.terminal.focus(row.terminal_id)
            end)
        end)
    end
    return session_action(function(session, row)
        local diagnostics = {}
        local agent_id = row.kind == "agent" and row.agent_id or nil
        if not agent_id then
            local ok, err, focused, values = api.agent.focused(session.id)
            if not ok then
                return false, err, nil, values
            end
            vim.list_extend(diagnostics, values or {})
            agent_id = focused and focused.id
        end
        local loaded, err, _, values = api.session.load(session.id)
        vim.list_extend(diagnostics, values or {})
        if not loaded and err ~= "session is already current" then
            return false, err, nil, diagnostics
        end
        if agent_id then
            local focused, focus_err, _, focus_values = api.agent.focus(session.id, agent_id)
            vim.list_extend(diagnostics, focus_values or {})
            -- Loading may already have committed; a focus failure is feedback,
            -- not a failed/rolled-back session switch.
            if not focused then
                diagnostics[#diagnostics + 1] = focus_err
            end
        end
        return true, nil, nil, diagnostics
    end)
end

local function focus_agent()
    local row = selected_row()
    local current = api.state.current()
    if not row or row.kind ~= "agent" or not current or current.id ~= row.session_id then
        return false
    end
    return session_action(function(session)
        return api.agent.focus(session.id, row.agent_id)
    end)
end

local function prompt_action(kind)
    local row = selected_row()
    if not row or (row.kind ~= "session" and row.kind ~= "agent") then
        return false
    end
    return run_action(function(finish, alive)
        local session, err = live_session(row.session_id)
        if not session then
            finish(function()
                return false, err
            end)
            return
        end
        local name = session.metadata.name
        vim.ui.input({
            prompt = kind == "rename" and ('Rename "' .. name .. '": ')
                or ('Mark "' .. name .. '" (a-z, 0-9): '),
            default = kind == "rename" and name or nil,
        }, function(value)
            finish(function()
                local trimmed = value ~= nil and vim.trim(value) or ""
                if trimmed == "" then
                    return nil
                end
                local target, target_err = live_session(row.session_id)
                if not target then
                    return false, target_err
                end
                if kind == "rename" then
                    return api.session.rename(target.id, trimmed)
                end
                local mark, parse_err = marks.parse(value)
                if not mark then
                    return false, parse_err
                end
                return marks.assign(target.id, mark, function()
                    return alive() and live_session(target.id) ~= nil
                end)
            end)
        end)
    end)
end

local function delete_session()
    return session_action(function(session, _, alive)
        local current = api.state.current()
        local message = table.concat({
            'Delete session "' .. session.metadata.name .. '"?',
            "Path: " .. session.metadata.cwd,
            "State: " .. (current and current.id == session.id and "current" or "active"),
            "This removes the stored session. Buffers and jobs are not deleted.",
        }, "\n")
        if vim.fn.confirm(message, "&Yes\n&No", 2) ~= 1 or not alive() then
            return nil
        end
        local target, err = live_session(session.id)
        if not target then
            return false, err
        end
        return api.session.delete(target.id)
    end)
end

local function clear_mark()
    return session_action(function(session)
        local ok, err, entries, diagnostics = api.session.list_marks()
        if not ok then
            return false, err, nil, diagnostics
        end
        for _, entry in ipairs(entries or {}) do
            if entry.id == session.id then
                local cleared, clear_err, item, values =
                    api.session.clear_mark(entry.mark, { expected_id = session.id })
                return cleared, clear_err, item, vim.list_extend(diagnostics or {}, values or {})
            end
        end
        return nil
    end)
end

local function redraw_view()
    local candidate, err = build(state.snapshot)
    if not candidate then
        report_error(err)
        return false
    end
    local committed, render_err = commit(state.snapshot, candidate)
    if not committed then
        report_error(render_err)
    end
    return committed
end

toggle_selected = function()
    if busy() then
        return false
    end
    local row = selected_row()
    if not row then
        return false
    end
    local key = row.expandable and row.key or row.parent_key
    if not key then
        return false
    end
    local previous = state.expanded[key]
    state.expanded[key] = not previous
    if redraw_view() then
        return true
    end
    state.expanded[key] = previous
    return false
end

local function expand_all()
    if busy() then
        return false
    end
    local previous = vim.deepcopy(state.expanded)
    local any_expanded = false
    for _, row in ipairs(state.rows) do
        if row.expandable and state.expanded[row.key] then
            any_expanded = true
            break
        end
    end
    for _, row in ipairs(state.rows) do
        if row.expandable then
            state.expanded[row.key] = not any_expanded
        end
    end
    if redraw_view() then
        return true
    end
    state.expanded = previous
    return false
end

local function cycle_sort()
    if busy() then
        return false
    end
    local previous = state.sort
    state.sort = search.next_sort(previous)
    if redraw_view() then
        return true
    end
    state.sort = previous
    return false
end

local function move_header(direction)
    if busy() then
        return false
    end
    local current = selected_index(state.rows) or 1
    local target
    if direction > 0 then
        for index = current + 1, #state.rows do
            if state.rows[index].expandable then
                target = index
                break
            end
        end
        if not target then
            for index, row in ipairs(state.rows) do
                if row.expandable then
                    target = index
                    break
                end
            end
        end
    else
        for index = current - 1, 1, -1 do
            if state.rows[index].expandable then
                target = index
                break
            end
        end
        if not target then
            for index = #state.rows, 1, -1 do
                if state.rows[index].expandable then
                    target = index
                    break
                end
            end
        end
    end
    if not target then
        return false
    end
    state.selected_key = state.rows[target].key
    render(state.rows, state.selected_key, true)
    return true
end

local function select_mouse()
    local position = vim.fn.getmousepos()
    if position.winid ~= state.win then
        return false
    end
    for index, line in ipairs(state.row_lines) do
        if line == position.line and state.rows[index] then
            state.selected_key = state.rows[index].key
            vim.api.nvim_win_set_cursor(state.win, { line, 0 })
            return true
        end
    end
    return false
end

local function install_mappings()
    local opts = { buffer = state.buf, noremap = true, silent = true, nowait = true }
    local function map(lhs, callback)
        -- r is also the prefix of rr; it must wait for the second key.
        vim.keymap.set("n", lhs, callback, vim.tbl_extend("force", opts, { nowait = lhs ~= "r" }))
    end
    map("<CR>", accept)
    map("<Tab>", toggle_selected)
    map("<S-Tab>", expand_all)
    map("<C-j>", function()
        return move_header(1)
    end)
    map("<C-k>", function()
        return move_header(-1)
    end)
    map("<C-r>", M.refresh)
    map("r", M.refresh)
    map("rr", function()
        return prompt_action("rename")
    end)
    map("uu", function()
        return session_action(function(session, _, alive)
            return require("sess.ui.unload")(session.id, alive)
        end)
    end)
    map("dd", delete_session)
    map("<C-b>", function()
        return prompt_action("mark")
    end)
    map("um", clear_mark)
    map("p", function()
        return session_action(function(session)
            return api.session.toggle_pin(session.id)
        end)
    end)
    map("<C-y>", function()
        return session_action(function(session)
            local result = vim.fn.setreg("+", session.metadata.cwd)
            if result ~= 0 then
                return false, "failed to copy session path"
            end
            return nil
        end)
    end)
    map("<C-o>", focus_agent)
    map("<C-s>", cycle_sort)
    map("?", function()
        local row = selected_row()
        local current = api.state.current()
        local reason = not row and "cursor is not on a session/agent row" or nil
        if row and row.kind ~= "session" and row.kind ~= "agent" then
            reason = "select a session/agent row"
        elseif row and not live_session(row.session_id) then
            reason = "session is no longer active"
        end
        local accept_reason = reason
        if row and (row.kind == "terminal" or row.kind == "background_terminals") then
            accept_reason = false
        end
        help.show({
            accept_reason = accept_reason,
            row_reason = reason,
            clear_reason = reason
                or (not (state.snapshot.marks_by_id or {})[row.session_id] and "session has no mark")
                or nil,
            focus_reason = reason
                or (row.kind ~= "agent" and "select an agent row")
                or (not current or current.id ~= row.session_id) and "agent session is not current"
                or nil,
            busy = state.pending_action ~= nil or state.refreshing,
            mouse = state.options.mouse,
        })
    end)
    map("q", M.close)
    map("<Esc>", M.close)
    if state.options.mouse then
        map("<LeftMouse>", select_mouse)
        map("<2-LeftMouse>", function()
            if select_mouse() then
                accept()
            end
        end)
    end
end

function M.configure(options)
    state.options = vim.tbl_deep_extend("force", vim.deepcopy(state.options), options or {})
    if state.options.enabled and state.options.toggle_key ~= false then
        local key = vim.api.nvim_replace_termcodes(state.options.toggle_key, true, false, true)
        if vim.fn.maparg(key, "n") == "" then
            vim.keymap.set(
                "n",
                state.options.toggle_key,
                M.toggle,
                { desc = "Toggle Sess sidebar", silent = true }
            )
        else
            log.warn("sidebar toggle key is already mapped: " .. state.options.toggle_key)
        end
    end
end

local function close_sidebar()
    if not state.open then
        return true
    end
    if not help.close() then
        return false, "failed to close sidebar help"
    end
    stop_polling()
    if valid_window(state.win) then
        local closed, err = close_owned_window(state.win)
        if not closed then
            return false, "failed to close sidebar window: " .. tostring(err)
        end
    end
    state.open = false
    state.instance, state.pending_action = nil, nil
    state.win, state.tab = nil, nil
    return true
end

function M.open()
    if state.cleanup_in_progress then
        return false, "sidebar cleanup in progress"
    end
    return run_operation("open", function()
        if not state.options.enabled then
            return false, "sidebar is disabled"
        end
        if state.open then
            local attached, attach_err = attach_current(nil, "open")
            if not attached then
                return false, attach_err
            end
            return true
        end
        local snapshot_ok, snapshot = pcall(api.active.initial_snapshot)
        if not snapshot_ok then
            return false, tostring(snapshot)
        end
        state.instance, state.pending_action = {}, nil
        state.sort = "default"
        state.expanded = initial_expansion(snapshot)
        local win, err = create_window()
        if not win then
            state.open, state.win, state.tab = false, nil, nil
            return false, err
        end
        state.open = true
        install_mappings()
        local candidate, build_err = build(snapshot)
        if not candidate then
            close_sidebar()
            return false, build_err
        end
        local committed, render_err = commit(snapshot, candidate)
        if not committed then
            close_sidebar()
            return false, render_err
        end
        start_polling()
        request_refresh()
        return true
    end)
end

function M.close()
    if state.cleanup_in_progress then
        return false, "sidebar cleanup in progress"
    end
    return run_operation("close", close_sidebar)
end

function M.toggle()
    if state.open then
        return M.close()
    end
    return M.open()
end

function M.is_open()
    return state.open and valid_window(state.win) or false
end

-- Internal UI seam: report only an attached edge split in the current tab.
function M.tabline_geometry()
    if
        not M.is_open()
        or state.tab ~= vim.api.nvim_get_current_tabpage()
        or vim.api.nvim_win_get_buf(state.win) ~= state.buf
    then
        return nil
    end
    local col = vim.api.nvim_win_get_position(state.win)[2]
    local width = vim.api.nvim_win_get_width(state.win)
    local at_edge = col == 0 or col + width == vim.o.columns
    if not at_edge or width >= vim.o.columns - 1 then
        return nil
    end
    return { win = state.win, col = col, width = width }
end

-- Called outside tabline evaluation; never probes metadata or mutates sessions.
function M.redraw_heading()
    local buffer_heading_visible = not tabline.heading_visible()
    if not M.is_open() or state.buffer_heading_visible == buffer_heading_visible then
        return
    end
    sync_selection()
    local ok, err = render(state.rows, state.selected_key)
    if not ok then
        report_error(err)
    end
end

function M.refresh()
    if not state.open then
        return false, "sidebar is closed"
    end
    if state.pending_action then
        return false, "sidebar action in progress"
    end
    local attached, attach_err = attach_current()
    if not attached then
        return false, attach_err
    end
    if state.refreshing then
        return true
    end
    return request_refresh({ marks = true })
end

function M.stop()
    stop_polling()
    return true
end

local function suspend_transient()
    if not state.open then
        return true
    end
    if not help.close() then
        return false, "failed to close sidebar help"
    end
    stop_polling()
    local old_win = state.win
    if valid_window(old_win) then
        local closed, err = close_owned_window(old_win)
        if not closed then
            -- Keep the owned window attached so a failed transition does not
            -- cause resume to create a duplicate split. Polling must also
            -- remain active because the owner is still visible.
            if valid_window(old_win) then
                start_polling()
            end
            return false, "failed to suspend sidebar window: " .. tostring(err)
        end
    end
    state.win, state.tab = nil, nil
    return true
end

local function resume_transient()
    if not state.open then
        return true
    end
    local attached, attach_err = attach_current(true)
    if not attached then
        stop_polling()
        local err = "sidebar could not attach after editor transition"
        if attach_err then
            err = err .. ": " .. tostring(attach_err)
        end
        report_error(err)
        return false, err
    end
    start_polling()
    return true
end

local function owned_window_closed(win)
    if state.closing_window or state.win ~= win then
        return
    end
    state.win, state.tab = nil, nil
    state.window_lost = true
    stop_polling()
    -- A tab close emits WinClosed before TabEnter for the replacement tab.
    -- Defer deciding whether this was an external close until that callback.
    vim.schedule(function()
        if not state.window_lost then
            return
        end
        state.window_lost = false
        state.open = false
        state.instance, state.pending_action = nil, nil
        help.close()
    end)
end

vim.api.nvim_create_autocmd("TabEnter", {
    group = sidebar_group,
    callback = function()
        if state.open and not editor.is_transient_ui_suspended() then
            if not help.close() then
                report_error("failed to close sidebar help on tab change")
                return
            end
            state.window_lost = false
            local content_win = vim.api.nvim_get_current_win()
            local attached, attach_err = attach_current()
            if attached and valid_window(content_win) and content_win ~= state.win then
                pcall(vim.api.nvim_set_current_win, content_win)
            elseif attach_err then
                report_error(attach_err)
            end
        end
    end,
})
vim.api.nvim_create_autocmd("WinClosed", {
    group = sidebar_group,
    callback = function(args)
        local win = tonumber(args.match)
        if win then
            owned_window_closed(win)
        end
    end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
    group = sidebar_group,
    callback = function(args)
        if state.buf == args.buf then
            state.cleanup_in_progress = true
            state.buf = nil
            if state.open and not state.closing_window then
                local win = state.win
                local closed, close_err = true, nil
                if valid_window(win) then
                    state.closing_window = true
                    closed, close_err = close_window(win)
                    state.closing_window = false
                    if not closed then
                        state.cleanup_in_progress = false
                        report_error(
                            "failed to close sidebar window after buffer wipe: "
                                .. tostring(close_err)
                        )
                        return
                    end
                end
                state.open, state.win, state.tab = false, nil, nil
                state.instance, state.pending_action = nil, nil
                help.close()
                stop_polling()
            end
            -- Keep the guard through the rest of the current autocmd event:
            -- a nested user callback must not reopen the sidebar after the
            -- owned window is closed but before this cleanup returns.
            vim.schedule(function()
                state.cleanup_in_progress = false
            end)
        end
    end,
})
local function on_resize()
    if not state.open then
        return
    end
    local resized, resize_err = resize_sidebar()
    if not resized then
        if resize_err then
            report_error(resize_err)
        end
        return
    end
    M.refresh()
end

vim.api.nvim_create_autocmd({ "VimResized", "WinResized" }, {
    group = sidebar_group,
    callback = on_resize,
})

local registered, registration_err = editor.register_transient_owner({
    suspend = suspend_transient,
    resume = resume_transient,
})
if not registered then
    log.warn("sidebar transient owner registration failed: " .. tostring(registration_err))
end

return M
