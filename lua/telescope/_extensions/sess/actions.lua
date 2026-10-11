local M = {}

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local api = require("sess.api")
local log = require("sess.log")
local finders = require("telescope._extensions.sess.finders")
local layout = require("telescope._extensions.sess.layout")
local load_or_create = require("sess.ui.load_or_create")
local marks = require("sess.ui.marks")
local selection = require("telescope._extensions.sess.selection")
local preview = require("telescope._extensions.sess.preview")
local search = require("telescope._extensions.sess.search")

-- Telescope callbacks can outlive the keypress that started them (notably
-- vim.ui.input). Keep the guard in this adapter so a second mapping cannot
-- start a competing lifecycle operation while the first one is pending.
local pending_actions = {}

local function clear_transient_action_status(picker)
    local status = picker and picker._sess_action_status
    if
        type(status) == "string"
        and not status:match("^Failed:")
        and not status:find("error", 1, true)
        and not status:find("diagnostic", 1, true)
    then
        picker._sess_action_status = nil
    end
end

local function copy_expanded(expanded)
    local copy = {}
    for session_id, is_expanded in pairs(expanded or {}) do
        copy[session_id] = is_expanded
    end
    return copy
end

-- Telescope refresh normally swaps its manager on the next input-loop turn,
-- but adapters and test doubles can mutate it before raising. Keep the
-- committed manager and rendered result rows available for rollback without
-- depending on private fields being present on every picker implementation.
local function capture_manager_fields(manager)
    if type(manager) ~= "table" then
        return nil
    end
    local ok, fields = pcall(function()
        local captured = {}
        for key, value in pairs(manager) do
            if type(value) == "table" then
                -- Keep row/entry identity intact while still copying manager
                -- containers that may be mutated in place during refresh.
                local array = true
                for child_key in pairs(value) do
                    if type(child_key) ~= "number" then
                        array = false
                        break
                    end
                end
                if array then
                    local copy = {}
                    for child_key, child_value in pairs(value) do
                        copy[child_key] = child_value
                    end
                    captured[key] = copy
                else
                    local copied, copy = pcall(vim.deepcopy, value)
                    captured[key] = copied and copy or value
                end
            else
                captured[key] = value
            end
        end
        return captured
    end)
    return ok and fields or nil
end

local function restore_manager_fields(manager, fields)
    if type(manager) ~= "table" or type(fields) ~= "table" then
        return
    end
    pcall(function()
        for key in pairs(manager) do
            manager[key] = nil
        end
        for key, value in pairs(fields) do
            manager[key] = value
        end
    end)
end

local function capture_refresh_prompt(picker)
    if not picker then
        return nil
    end
    if type(picker.get_prompt) == "function" then
        local ok, prompt = pcall(picker.get_prompt, picker)
        if ok and type(prompt) == "string" then
            return prompt
        end
    end
    if type(action_state.get_current_line) == "function" then
        local ok, prompt = pcall(action_state.get_current_line)
        if ok and type(prompt) == "string" then
            return prompt
        end
    end
    -- Keep lightweight picker fakes usable when they do not implement either
    -- Telescope prompt API.
    if type(picker.prompt) == "string" then
        return picker.prompt
    end
    local prompt_bufnr = picker.prompt_bufnr
    if type(prompt_bufnr) == "number" then
        local ok, prompt = pcall(function()
            if not vim.api.nvim_buf_is_valid(prompt_bufnr) then
                return nil
            end
            return vim.api.nvim_buf_get_lines(prompt_bufnr, 0, 1, false)[1]
        end)
        if ok and type(prompt) == "string" then
            return prompt
        end
    end
    return nil
end

local function capture_refresh_state(picker)
    local pending_selection = picker and picker._sess_pending_selection_restore
    local state = {
        finder = picker and picker.finder,
        manager = picker and picker.manager,
        manager_fields = capture_manager_fields(picker and picker.manager),
        multi = picker and picker._multi,
        selection_entry = picker and picker._selection_entry,
        selection_row = picker and picker._selection_row,
        pending_selection_restore = pending_selection,
        prompt_title = picker and picker.prompt_title,
        snapshot = picker and picker._sess_active_snapshot,
        expanded = picker and picker._sess_expanded,
        expanded_fields = copy_expanded(picker and picker._sess_expanded),
        active_expand = picker and picker._sess_active_expand,
        path_mode = picker and picker._sess_path_mode,
        prompt = capture_refresh_prompt(picker),
    }
    if pending_selection then
        state.pending_selection_fields = {
            finder = pending_selection.finder,
            key = vim.deepcopy(pending_selection.key),
            opts = vim.deepcopy(pending_selection.opts),
        }
    end
    local prompt_border = picker
        and picker.layout
        and picker.layout.prompt
        and picker.layout.prompt.border
    if prompt_border then
        -- A nil title is meaningful: rollback must clear a candidate title
        -- introduced by a partially failed refresh.
        state.border_title_present = true
        state.border_title = prompt_border.title
    end
    if picker and type(picker.get_selection) == "function" then
        local ok, selected = pcall(picker.get_selection, picker)
        if ok then
            state.selected = selected
        end
    end
    local results_bufnr = picker and picker.results_bufnr
    if type(results_bufnr) == "number" then
        local valid, is_valid = pcall(vim.api.nvim_buf_is_valid, results_bufnr)
        if valid and is_valid then
            local ok, rows = pcall(vim.api.nvim_buf_get_lines, results_bufnr, 0, -1, false)
            if ok then
                state.rows = rows
            end
        end
    end
    local results_win = picker and picker.results_win
    if type(results_win) == "number" then
        local valid, is_valid = pcall(vim.api.nvim_win_is_valid, results_win)
        if valid and is_valid then
            local ok, cursor = pcall(vim.api.nvim_win_get_cursor, results_win)
            if ok then
                state.cursor = cursor
            end
        end
    end
    return state
end

local function restore_refresh_state(picker, state)
    if not picker or not state then
        return
    end
    picker.finder = state.finder
    if state.manager ~= nil or picker.manager ~= nil then
        picker.manager = state.manager
    end
    restore_manager_fields(state.manager, state.manager_fields)
    picker._multi = state.multi
    picker._selection_entry = state.selection_entry
    picker._selection_row = state.selection_row
    picker._sess_pending_selection_restore = state.pending_selection_restore
    if state.pending_selection_restore and state.pending_selection_fields then
        state.pending_selection_restore.finder = state.pending_selection_fields.finder
        state.pending_selection_restore.key = state.pending_selection_fields.key
        state.pending_selection_restore.opts = state.pending_selection_fields.opts
    end
    picker.prompt_title = state.prompt_title
    picker._sess_active_snapshot = state.snapshot
    picker._sess_active_expand = state.active_expand
    picker._sess_path_mode = state.path_mode
    picker._sess_expanded = state.expanded
    if type(state.expanded) == "table" and type(state.expanded_fields) == "table" then
        for key in pairs(state.expanded) do
            state.expanded[key] = nil
        end
        for key, value in pairs(state.expanded_fields) do
            state.expanded[key] = value
        end
    end
    local prompt_border = picker.layout
        and picker.layout.prompt
        and picker.layout.prompt.border
    if prompt_border and state.border_title_present then
        pcall(prompt_border.change_title, prompt_border, state.border_title)
    end
    if state.prompt ~= nil then
        local restored = false
        if type(picker.set_prompt) == "function" then
            restored = pcall(picker.set_prompt, picker, state.prompt)
        end
        if not restored and picker.prompt ~= nil then
            -- Lightweight picker fakes may expose only a prompt field.
            restored = pcall(function()
                picker.prompt = state.prompt
            end)
        end
        if not restored and type(picker.prompt_bufnr) == "number" then
            pcall(function()
                if vim.api.nvim_buf_is_valid(picker.prompt_bufnr) then
                    vim.api.nvim_buf_set_lines(picker.prompt_bufnr, 0, 1, false, { state.prompt })
                end
            end)
        end
    end

    if state.rows ~= nil and type(picker.results_bufnr) == "number" then
        pcall(function()
            if vim.api.nvim_buf_is_valid(picker.results_bufnr) then
                vim.api.nvim_buf_set_lines(picker.results_bufnr, 0, -1, false, state.rows)
            end
        end)
    end
    if state.cursor ~= nil and type(picker.results_win) == "number" then
        pcall(function()
            if vim.api.nvim_win_is_valid(picker.results_win) then
                vim.api.nvim_win_set_cursor(picker.results_win, state.cursor)
            end
        end)
    end

    local key = selection.key(state.selected and (state.selected.value or state.selected))
    if key then
        pcall(selection.restore, picker, state.finder, key, { parent = true })
    end
    -- Preserve the exact Telescope entry object when an adapter exposed one;
    -- selection.restore above is still needed to redraw real picker rows.
    picker._selection_entry = state.selection_entry
    picker._selection_row = state.selection_row
    if state.selection_entry ~= nil then
        pcall(function()
            require("telescope.state").set_global_key("selected_entry", state.selection_entry)
        end)
    end
end

local function current_picker(prompt_bufnr)
    local ok, picker = pcall(action_state.get_current_picker, prompt_bufnr)
    return ok and picker or nil
end

local function begin_action(prompt_bufnr)
    local picker = current_picker(prompt_bufnr)
    if pending_actions[prompt_bufnr] or (picker and picker._sess_action_pending) then
        return nil, false
    end
    pending_actions[prompt_bufnr] = true
    if picker then
        picker._sess_action_pending = true
        picker._sess_action_status = "Working..."
    end
    return picker, true
end

local function finish_action(prompt_bufnr, picker, status)
    pending_actions[prompt_bufnr] = nil
    if picker then
        picker._sess_action_pending = false
        local current_status = picker._sess_action_status
        -- report_result records the actionable operation error (or diagnostic
        -- summary); generic completion labels must not erase it.
        if
            (
                status == "Failed"
                and type(current_status) == "string"
                and current_status:match("^Failed:")
            )
            or (
                status == "Done"
                and type(current_status) == "string"
                and current_status ~= "Working..."
                and current_status ~= "Done"
            )
            or (status == "Focused agent" and current_status == "Done with diagnostics")
        then
            return
        end
        picker._sess_action_status = status
    end
end

-- Refreshes shared by picker hydration, resize, and lifecycle actions must not
-- leave Telescope half-switched when a finder or renderer raises after mutating
-- its manager. Keep this transaction independent of prompt-buffer lookup so
-- background hydration can use the same rollback path.
function M.transactional_refresh(picker, next_finder, key)
    if not picker or type(picker.refresh) ~= "function" or picker._sess_refreshing then
        return false
    end
    local rollback = capture_refresh_state(picker)
    picker._sess_refreshing = true
    selection.queue(picker, next_finder, key)
    local ok = pcall(function()
        picker:refresh(next_finder, { reset_prompt = false })
        if not selection.is_attached(picker) then
            selection.restore_pending(picker)
        end
    end)
    if not ok then
        selection.cancel(picker)
        restore_refresh_state(picker, rollback)
    end
    picker._sess_refreshing = false
    return ok
end

---@param prompt_bufnr number
---@param finder table|nil
---@param key table|nil
---@return boolean
local function refresh(prompt_bufnr, finder, key)
    local picker = current_picker(prompt_bufnr)
    if not picker or type(picker.refresh) ~= "function" or picker._sess_refreshing then
        return false
    end
    if type(picker._sess_invalidate_finder_hydration) == "function" then
        picker._sess_invalidate_finder_hydration()
    end
    clear_transient_action_status(picker)
    if not key then
        local ok, selected = pcall(action_state.get_selected_entry)
        key = ok and selection.key(selected and selected.value)
    end
    preview.invalidate(picker)
    local display_opts = {
        available_width = layout.available_width(picker),
        result_width = layout.result_width(picker),
        mode = picker._sess_display_mode,
    }
    local next_finder = finder
    if not next_finder and picker._sess_path_mode then
        local ok, prompt = pcall(action_state.get_current_line)
        next_finder = finders.generate_directory_finder(
            ok and prompt or "",
            display_opts,
            nil,
            nil,
            picker._sess_search_options
        )
    end
    next_finder = next_finder or finders.generate_new_finder(
        display_opts,
        nil,
        nil,
        picker._sess_search_options
    )
    -- Mutations redraw the preview and rows without discarding user input. The
    -- shared transaction also protects background hydration and resize paths.
    return M.transactional_refresh(picker, next_finder, key)
end

local function report_result(picker, ok, err, diagnostics)
    if not ok then
        log.error(err)
        if picker then
            picker._sess_action_status = "Failed: " .. tostring(err)
        end
        return false
    end
    log.diagnostics(diagnostics)
    if picker then
        picker._sess_action_status = #(diagnostics or {}) > 0 and "Done with diagnostics" or "Done"
    end
    return true
end

---@return Sess.TelescopeSessionEntry | nil
local function selected_value()
    local selected = action_state.get_selected_entry()
    if not selected then
        return nil
    end

    return selected.value
end

local function selected_path(value)
    if not value then
        return nil
    end
    if value.directory then
        return value.path
    end
    local session = value.session or value
    return session.metadata and session.metadata.cwd or nil
end

local function picker_is_alive(picker)
    if not picker or picker.closed == true or picker._sess_picker_closed then
        return false
    end
    if type(picker.is_done) == "function" then
        local ok, done = pcall(picker.is_done, picker)
        if ok and done then
            return false
        end
    end
    return true
end

local function next_active_refresh_generation(picker)
    local generation = (picker._sess_active_refresh_generation or 0) + 1
    picker._sess_active_refresh_generation = generation
    return generation
end

local function update_active_title(picker, snapshot)
    local title = finders.active_dashboard_title(snapshot)
    picker.prompt_title = title
    local prompt_border = picker.layout
        and picker.layout.prompt
        and picker.layout.prompt.border
    if prompt_border and type(prompt_border.change_title) == "function" then
        prompt_border:change_title(title)
    end
end

---@param prompt_bufnr number
---@return nil
function M.enter(prompt_bufnr)
    local value = selected_value()
    if not value then
        return
    end
    local picker, started = begin_action(prompt_bufnr)
    if not started then
        return
    end

    -- Enter replaces the current layout, so retain the existing close-before-
    -- transition contract even when the lifecycle operation later fails.
    actions.close(prompt_bufnr)

    local ok, err, _, diagnostics
    if value.directory then
        ok, err, _, diagnostics = load_or_create.run(value.path)
    elseif value.id == nil then
        ok, err, _, diagnostics = api.session.create(value.metadata.cwd)
    else
        ok, err, _, diagnostics = api.session.load(value.id)
    end

    report_result(picker, ok, err, diagnostics)
    finish_action(prompt_bufnr, picker, ok and "Done" or "Failed")
end

---@param prompt_bufnr number
---@return nil
local function refresh_active(prompt_bufnr, expanded, search_options)
    local picker = action_state.get_current_picker(prompt_bufnr)
    clear_transient_action_status(picker)
    preview.invalidate(picker)
    local selected = action_state.get_selected_entry()
    local key = selection.key(selected and selected.value)
    local previous_snapshot = picker._sess_active_snapshot
    local snapshot = previous_snapshot or api.active.snapshot()
    search_options = search_options or picker._sess_search_options
    -- Expansion changes are speculative until Telescope accepts the candidate
    -- finder. Keep the committed table untouched so a failed refresh cannot
    -- lose the user's previous view.
    local candidate_expanded = copy_expanded(expanded)
    local rollback = capture_refresh_state(picker)
    local ok = pcall(function()
        local finder = finders.generate_active_finder_from_snapshot(
            snapshot,
            candidate_expanded,
            picker._sess_active_expand,
            { available_width = layout.available_width(picker) },
            search_options
        )
        selection.queue(picker, finder, key, { parent = true })
        picker:refresh(finder, { reset_prompt = false })
        if not selection.is_attached(picker) then
            selection.restore_pending(picker)
        end
        picker._sess_active_snapshot = snapshot
        picker._sess_expanded = candidate_expanded
    end)
    if not ok then
        selection.cancel(picker)
        restore_refresh_state(picker, rollback)
        picker._sess_active_snapshot = previous_snapshot
    end
    return ok
end

function M.toggle_active(prompt_bufnr)
    local value = selected_value()
    if not value or (value.kind ~= "session" and value.kind ~= "agent") then
        return
    end

    local picker = action_state.get_current_picker(prompt_bufnr)
    if not picker or picker._sess_action_pending or picker._sess_refreshing then
        return
    end
    local expanded = copy_expanded(picker._sess_expanded)
    local session_id = value.session_id
    expanded[session_id] = not expanded[session_id]
    refresh_active(prompt_bufnr, expanded)
end

function M.toggle_all_active(prompt_bufnr)
    local picker = action_state.get_current_picker(prompt_bufnr)
    if not picker or picker._sess_action_pending or picker._sess_refreshing then
        return
    end
    local expanded = copy_expanded(picker._sess_expanded)
    local active_snapshot = picker._sess_active_snapshot
    local sessions = active_snapshot and active_snapshot.sessions or api.state.active()
    local any_expanded = false
    for _, session in ipairs(sessions) do
        if expanded[session.id] then
            any_expanded = true
            break
        end
    end
    for _, session in ipairs(sessions) do
        expanded[session.id] = not any_expanded
    end
    refresh_active(prompt_bufnr, expanded)
end

local function active_entries(picker)
    local entries = picker and picker.manager and picker.manager.entries
    if type(entries) == "table" and #entries > 0 then
        return entries
    end
    return picker and picker.finder and picker.finder.results or {}
end

local function navigate_active_header(prompt_bufnr, direction)
    local picker = current_picker(prompt_bufnr)
    if not picker or picker._sess_action_pending or picker._sess_refreshing then
        return
    end

    local entries = active_entries(picker)
    local selected = action_state.get_selected_entry()
    local selected_key = selection.key(selected and selected.value)
    local selected_index
    for index, entry in ipairs(entries) do
        local key = selection.key(entry.value or entry)
        if
            key
            and selected_key
            and key.id == selected_key.id
            and key.kind == selected_key.kind
            and key.agent_id == selected_key.agent_id
        then
            selected_index = index
            break
        end
    end

    local headers = {}
    for index, entry in ipairs(entries) do
        local value = entry.value or entry
        if value.kind == "session" then
            headers[#headers + 1] = { index = index, value = value }
        end
    end
    if #headers == 0 then
        return
    end

    local target
    if selected_index then
        if direction > 0 then
            for _, header in ipairs(headers) do
                if header.index > selected_index then
                    target = header
                    break
                end
            end
            target = target or headers[1]
        else
            for index = #headers, 1, -1 do
                if headers[index].index < selected_index then
                    target = headers[index]
                    break
                end
            end
            target = target or headers[#headers]
        end
    else
        target = direction > 0 and headers[1] or headers[#headers]
    end

    selection.restore(picker, picker.finder, selection.key(target.value))
end

function M.next_active_header(prompt_bufnr)
    navigate_active_header(prompt_bufnr, 1)
end

function M.previous_active_header(prompt_bufnr)
    navigate_active_header(prompt_bufnr, -1)
end

-- Short aliases are useful for user mappings while the descriptive names keep
-- action help and integrations discoverable.
M.active_next_header = M.next_active_header
M.active_previous_header = M.previous_active_header

function M.active_enter(prompt_bufnr)
    local value = selected_value()
    if not value or (value.kind ~= "session" and value.kind ~= "agent") then
        return
    end
    local picker, started = begin_action(prompt_bufnr)
    if not started then
        return
    end

    local agent_id = value.kind == "agent" and value.agent_id
    if not agent_id then
        local _, _, focused = api.agent.focused(value.session_id)
        agent_id = focused and focused.id or nil
    end
    actions.close(prompt_bufnr)
    local ok, err, _, diagnostics = api.session.load(value.session_id)
    if not report_result(picker, ok, err, diagnostics) then
        finish_action(prompt_bufnr, picker, "Failed")
        return
    end

    if agent_id then
        local focused, focus_err, _, focus_diagnostics = api.agent.focus(value.session_id, agent_id)
        if not focused then
            log.error(focus_err)
            if picker then
                picker._sess_action_status = "Done with focus error"
            end
        end
        log.diagnostics(focus_diagnostics)
    end
    finish_action(prompt_bufnr, picker, "Done")
end

function M.cycle_sort(prompt_bufnr)
    local picker = current_picker(prompt_bufnr)
    if not picker or picker._sess_refreshing or picker._sess_action_pending then
        return
    end
    local previous_options = picker._sess_search_options
    local options = previous_options or {}
    local previous_mode = picker._sess_sort_mode or options.sort or "default"
    local next_mode = search.next_sort(previous_mode)
    local next_options = vim.tbl_deep_extend("force", {}, options, { sort = next_mode })
    local selected = action_state.get_selected_entry()
    local selected_key = selection.key(selected and selected.value)
    local previous_status = picker._sess_action_status
    local previous_sort = picker._sess_sort_mode
    local refreshed
    local ok = pcall(function()
        picker._sess_search_options = next_options
        picker._sess_sort_mode = next_mode
        if picker._sess_help_kind == "active" then
            refreshed = refresh_active(prompt_bufnr, picker._sess_expanded or {}, next_options)
        else
            refreshed = refresh(prompt_bufnr, nil, selected_key)
        end
    end)
    if not ok or not refreshed then
        -- refresh() rolls back rendered state; this restores the sort state that
        -- describes that still-committed view, including any prior diagnostic.
        picker._sess_search_options = previous_options
        picker._sess_sort_mode = previous_sort
        picker._sess_action_status = previous_status
        return
    end
    picker._sess_action_status = "Sort: " .. next_mode
end

function M.toggle_display(prompt_bufnr)
    local picker = current_picker(prompt_bufnr)
    if not picker or picker._sess_refreshing or picker._sess_action_pending then
        return
    end
    local config = require("telescope._extensions.sess.config")
    local display = config.values.display or {}
    local current = picker._sess_display_mode
        or layout.display_mode(display, layout.result_width(picker))
    local previous_mode = picker._sess_display_mode
    picker._sess_display_mode = current == "compact" and "detailed" or "compact"
    local selected = action_state.get_selected_entry()
    if not refresh(prompt_bufnr, nil, selection.key(selected and selected.value)) then
        picker._sess_display_mode = previous_mode
    end
end

function M.show_action_help(prompt_bufnr, kind, mappings, options)
    local help = require("telescope._extensions.sess.help")
    if not kind or not mappings then
        local picker = action_state.get_current_picker(prompt_bufnr)
        kind = kind or (picker and picker._sess_help_kind) or "regular"
        mappings = mappings or (picker and picker._sess_help_mappings)
        options = options or (picker and picker._sess_help_options)
    end
    if mappings then
        help.show(prompt_bufnr, kind, mappings, options or {})
    end
end

function M.copy_path(prompt_bufnr)
    local value = selected_value()
    local path = selected_path(value)
    if not path or path == "" then
        return
    end
    local picker, started = begin_action(prompt_bufnr)
    if not started then
        return
    end

    local ok, err = pcall(vim.fn.setreg, "+", path)
    if not ok then
        log.error("failed to copy session path: " .. tostring(err))
        finish_action(prompt_bufnr, picker, "Failed")
        return
    end
    finish_action(prompt_bufnr, picker, "Copied path")
end

-- Descriptive aliases make the action useful to callers defining their own
-- mappings without coupling them to the footer wording.
M.copy_session_path = M.copy_path

function M.focus_agent(prompt_bufnr)
    local value = selected_value()
    if not value or value.kind ~= "agent" or not value.session_id or not value.agent_id then
        return
    end
    local picker, started = begin_action(prompt_bufnr)
    if not started then
        return
    end

    local ok, err, _, diagnostics = api.agent.focus(value.session_id, value.agent_id)
    if not report_result(picker, ok, err, diagnostics) then
        finish_action(prompt_bufnr, picker, "Failed")
        return
    end
    -- Focus can complete while the API reports non-fatal diagnostics;
    -- finish_action deliberately retains that actionable feedback.
    finish_action(prompt_bufnr, picker, "Focused agent")
end

M.focus_selected_agent = M.focus_agent

function M.refresh_active(prompt_bufnr)
    local value = selected_value()
    local active_picker = current_picker(prompt_bufnr)
    if not picker_is_alive(active_picker) then
        return
    end
    local picker, started = begin_action(prompt_bufnr)
    if not started then
        return
    end

    local expanded = copy_expanded(picker._sess_expanded)
    local key = selection.key(value)
    local previous_snapshot = picker._sess_active_snapshot
    local generation = next_active_refresh_generation(picker)
    picker._sess_active_loading = true
    picker._sess_active_refresh_warning = nil
    local previous_title = picker.prompt_title
    local rollback
    local completed = false
    local function finish_refresh(ok, status)
        if completed then
            return
        end
        completed = true
        picker._sess_active_refresh_cancel = nil
        picker._sess_active_loading = false
        if not ok then
            picker._sess_active_refresh_warning = tostring(status or "refresh failed")
            -- The queued key belongs to the candidate finder only. Never let
            -- a failed refresh leave a later completion callback probing it.
            selection.cancel(picker)
            restore_refresh_state(picker, rollback)
            picker.prompt_title = previous_title
            picker._sess_active_snapshot = previous_snapshot
        end
        finish_action(prompt_bufnr, picker, status or (ok and "Refreshed" or "Failed"))
    end

    local function on_snapshot(snapshot)
        if completed then
            return
        end
        if picker._sess_active_refresh_generation ~= generation then
            -- A polling refresh (or a newer manual refresh) owns the picker
            -- now. Do not roll back or clear its cancellation handle while
            -- retiring this stale action callback.
            completed = true
            finish_action(prompt_bufnr, picker, "Cancelled")
            return
        end
        if current_picker(prompt_bufnr) ~= picker or not picker_is_alive(picker) then
            finish_refresh(false, "Cancelled")
            return
        end
        local ok, result = pcall(function()
            if picker._sess_active_refresh_generation ~= generation then
                return false
            end
            local finder = finders.generate_active_finder_from_snapshot(
                snapshot,
                expanded,
                picker._sess_active_expand,
                {
                    available_width = layout.available_width(picker),
                    result_width = layout.result_width(picker),
                },
                picker._sess_search_options
            )
            -- Queue selection only for the candidate finder. The old snapshot,
            -- title, manager, and rendered rows remain committed until
            -- Telescope accepts it.
            rollback = capture_refresh_state(picker)
            if picker._sess_active_refresh_generation ~= generation then
                return false
            end
            selection.queue(picker, finder, key, { parent = true })
            picker:refresh(finder, { reset_prompt = false })
            if not selection.is_attached(picker) then
                selection.restore_pending(picker)
            end
            picker._sess_active_snapshot = snapshot
            picker._sess_expanded = expanded
            picker._sess_active_loading = false
            picker._sess_active_refresh_warning = nil
            preview.invalidate(picker)
            update_active_title(picker, snapshot)
            return true
        end)
        if ok and result == false then
            completed = true
            finish_action(prompt_bufnr, picker, "Cancelled")
            return
        end
        finish_refresh(ok, ok and "Refreshed" or "Failed")
        if not ok then
            log.error(result)
        end
    end

    local ok, cancel = pcall(function()
        return api.active.snapshot_async(on_snapshot, {
            previous_snapshot = previous_snapshot,
        })
    end)
    if not ok then
        finish_refresh(false, "Failed")
        log.error(cancel)
        return
    end
    if type(cancel) == "function" and not completed then
        picker._sess_active_refresh_cancel = cancel
    elseif not completed then
        -- snapshot_async must either complete the callback or provide a
        -- cancellation handle. Treat any other return as a failed request so
        -- the action guard cannot remain stuck indefinitely.
        finish_refresh(false, "Failed")
    end
end

-- Picker lifecycle hooks call this when the prompt/results windows disappear.
-- Keep cancellation here so asynchronous refreshes cannot retain an action
-- lock after Telescope has discarded the picker.
function M.on_picker_close(picker)
    if not picker then
        return
    end
    picker._sess_picker_closed = true
    local cancel = picker._sess_active_refresh_cancel
    picker._sess_active_refresh_cancel = nil
    if type(cancel) == "function" then
        pcall(cancel)
    end
    selection.cancel(picker)
    finish_action(picker.prompt_bufnr, picker, "Cancelled")
end

M.refresh_active_agents = M.refresh_active

function M.complete_path(prompt_bufnr)
    local value = selected_value()
    if not value or not value.directory or not value.prompt then
        return
    end

    local picker = action_state.get_current_picker(prompt_bufnr)
    local prompt = value.prompt
    if prompt:sub(-1) ~= "/" then
        prompt = prompt .. "/"
    end
    picker:set_prompt(prompt)
end

---@param prompt_bufnr number
---@return nil
function M.restore_session(prompt_bufnr)
    local value = selected_value()
    if not value then
        return
    end
    local picker, started = begin_action(prompt_bufnr)
    if not started then
        return
    end
    local key = selection.key(value)
    local ok, err, _, diagnostics = api.session.restore(value.key)
    if not report_result(picker, ok, err, diagnostics) then
        finish_action(prompt_bufnr, picker, "Failed")
        return
    end

    finish_action(prompt_bufnr, picker, "Done")
    refresh(
        prompt_bufnr,
        finders.generate_deleted_finder({
            available_width = layout.available_width(picker),
        }),
        key
    )
end

function M.delete_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end
    local picker, started = begin_action(prompt_bufnr)
    if not started then
        return
    end
    local key = selection.key(value)
    local name = value.metadata and value.metadata.name or value.id
    local cwd = value.metadata and value.metadata.cwd or "unknown"
    local current = api.state.current()
    local deleting_current = current and current.id == value.id
    local state = deleting_current and "current" or "inactive"
    local message = table.concat({
        'Delete session "' .. name .. '"?',
        "",
        "Path: " .. cwd,
        "State: " .. state,
        "This will remove the stored session. Buffers and jobs are not deleted.",
    }, "\n")

    if vim.fn.confirm(message, "&Yes\n&No", 2) ~= 1 then
        finish_action(prompt_bufnr, picker, "Cancelled")
        return
    end

    -- A current-session deletion replaces the layout, including picker windows.
    if deleting_current then
        actions.close(prompt_bufnr)
    end

    local ok, err, _, diagnostics = api.session.delete(value.id)
    if not report_result(picker, ok, err, diagnostics) then
        finish_action(prompt_bufnr, picker, "Failed")
        return
    end

    finish_action(prompt_bufnr, picker, "Done")
    if not deleting_current then
        refresh(prompt_bufnr, nil, key)
    end
end

---@param prompt_bufnr number
---@return nil
function M.unload_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end
    local picker, started = begin_action(prompt_bufnr)
    if not started then
        return
    end
    local key = selection.key(value)
    local current = api.state.current()
    local unloading_current = current and current.id == value.id

    -- Close before capturing the current session so picker windows aren't saved.
    if unloading_current then
        actions.close(prompt_bufnr)
    end

    local ok, err, _, diagnostics = require("sess.ui.unload")(value.id)
    if not ok then
        if err == "unload cancelled" then
            log.info("Unload cancelled")
        else
            log.error(err)
        end
        finish_action(prompt_bufnr, picker, err == "unload cancelled" and "Cancelled" or "Failed")
        return
    end

    log.diagnostics(diagnostics)
    finish_action(prompt_bufnr, picker, "Done")
    if not unloading_current then
        refresh(prompt_bufnr, nil, key)
    end
end

---@param prompt_bufnr number
---@return nil
function M.mark_session(prompt_bufnr)
    local value = selected_value()
    local is_active = value and value.kind ~= nil
    local session_id = value and (value.id or value.session_id)
    if not session_id then
        return
    end
    if is_active and value.kind ~= "session" and value.kind ~= "agent" then
        return
    end
    local picker, started = begin_action(prompt_bufnr)
    if not started then
        return
    end
    local key = selection.key(value)
    vim.ui.input({ prompt = "Mark (a-z, 0-9): " }, function(input)
        if not input then
            finish_action(prompt_bufnr, picker, "Cancelled")
            return
        end
        local mark, parse_err = marks.parse(input)
        if not mark then
            log.error(parse_err)
            finish_action(prompt_bufnr, picker, "Failed")
            return
        end
        local ok, err, _, diagnostics = marks.assign(session_id, mark)
        if not report_result(picker, ok, err, diagnostics) then
            finish_action(prompt_bufnr, picker, "Failed")
            return
        end
        finish_action(prompt_bufnr, picker, "Done")
        if is_active then
            -- Force one complete snapshot after a mark mutation; subsequent
            -- status polls can reuse the refreshed mark map.
            picker = current_picker(prompt_bufnr) or picker
            if picker then
                picker._sess_active_snapshot = nil
                refresh_active(prompt_bufnr, picker._sess_expanded or {})
            end
        else
            refresh(prompt_bufnr, nil, key)
        end
    end)
end

function M.toggle_pin_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end
    local picker, started = begin_action(prompt_bufnr)
    if not started then
        return
    end
    local key = selection.key(value)
    local ok, err, _, diagnostics = api.session.toggle_pin(value.id)
    if not report_result(picker, ok, err, diagnostics) then
        finish_action(prompt_bufnr, picker, "Failed")
        return
    end

    finish_action(prompt_bufnr, picker, "Done")
    refresh(prompt_bufnr, nil, key)
end

---@param prompt_bufnr number
---@return nil
function M.unmark_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end
    local _, _, entries = api.session.list_marks()
    local mark
    for _, entry in ipairs(entries or {}) do
        if entry.id == value.id then
            mark = entry.mark
            break
        end
    end
    if not mark then
        return
    end
    local picker, started = begin_action(prompt_bufnr)
    if not started then
        return
    end
    local key = selection.key(value)
    local ok, err, _, diagnostics = api.session.clear_mark(mark)
    if not report_result(picker, ok, err, diagnostics) then
        finish_action(prompt_bufnr, picker, "Failed")
        return
    end
    finish_action(prompt_bufnr, picker, "Done")
    refresh(prompt_bufnr, nil, key)
end

function M.rename_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end
    local picker, started = begin_action(prompt_bufnr)
    if not started then
        return
    end
    local key = selection.key(value)

    vim.ui.input({
        prompt = "Enter Session Name: ",
        default = value.metadata and value.metadata.name or "",
    }, function(name)
        if not name then
            finish_action(prompt_bufnr, picker, "Cancelled")
            return
        end

        name = vim.trim(name)
        if name == "" then
            finish_action(prompt_bufnr, picker, "Cancelled")
            return
        end

        local ok, err, _, diagnostics = api.session.rename(value.id, name)
        if not report_result(picker, ok, err, diagnostics) then
            finish_action(prompt_bufnr, picker, "Failed")
            return
        end

        finish_action(prompt_bufnr, picker, "Done")
        refresh(prompt_bufnr, nil, key)
    end)
end

return M
