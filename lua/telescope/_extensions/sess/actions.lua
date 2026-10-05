local M = {}

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local api = require("sess.api")
local log = require("sess.log")
local finders = require("telescope._extensions.sess.finders")
local layout = require("telescope._extensions.sess.layout")
local load_or_create = require("sess.ui.load_or_create")
local marks = require("sess.ui.marks")

-- Telescope callbacks can outlive the keypress that started them (notably
-- vim.ui.input). Keep the guard in this adapter so a second mapping cannot
-- start a competing lifecycle operation while the first one is pending.
local pending_actions = {}

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
        picker._sess_action_status = status
    end
end

local function selection_key(value)
    if not value then
        return nil
    end
    local id = value.id or value.session_id
    if not id then
        return nil
    end
    return {
        id = id,
        kind = value.kind,
        agent_id = value.agent_id,
    }
end

local function same_selection_key(left, right)
    return left
        and right
        and left.id == right.id
        and left.kind == right.kind
        and left.agent_id == right.agent_id
end

local function restore_selection(picker, finder, key)
    if type(picker.set_selection) ~= "function" then
        return
    end
    for index, row in ipairs(finder.results or {}) do
        if
            same_selection_key(selection_key(row), key)
            or same_selection_key(selection_key(row.value), key)
        then
            pcall(picker.set_selection, picker, index)
            return
        end
    end

    -- A successful mutation can remove the selected row. Let Telescope select
    -- the first remaining row rather than retaining a stale entry.
    if key and #(finder.results or {}) > 0 then
        pcall(picker.set_selection, picker, 1)
    end
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
    if not key then
        local ok, selected = pcall(action_state.get_selected_entry)
        key = ok and selection_key(selected and selected.value) or nil
    end
    local next_finder = finder
        or finders.generate_new_finder({
            available_width = layout.available_width(picker),
        })
    -- Mutations redraw the preview and rows without discarding user input. The
    -- local flag also prevents a refresh callback from recursively refreshing.
    picker._sess_refreshing = true
    local ok = pcall(function()
        picker:refresh(next_finder, { reset_prompt = false })
        restore_selection(picker, next_finder, key)
    end)
    picker._sess_refreshing = false
    return ok
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
local function refresh_active(prompt_bufnr, expanded)
    local picker = action_state.get_current_picker(prompt_bufnr)
    local selected = action_state.get_selected_entry()
    local key = selection_key(selected and selected.value)
    local snapshot = picker._sess_active_snapshot or api.active.snapshot()
    picker._sess_active_snapshot = snapshot
    local finder = finders.generate_active_finder_from_snapshot(
        snapshot,
        expanded,
        picker._sess_active_expand,
        { available_width = layout.available_width(picker) }
    )
    picker:refresh(finder, { reset_prompt = false })
    restore_selection(picker, finder, key)
end

function M.toggle_active(prompt_bufnr)
    local value = selected_value()
    if not value or (value.kind ~= "session" and value.kind ~= "agent") then
        return
    end

    local picker = action_state.get_current_picker(prompt_bufnr)
    local expanded = picker._sess_expanded or {}
    local session_id = value.session_id
    expanded[session_id] = not expanded[session_id]
    picker._sess_expanded = expanded
    refresh_active(prompt_bufnr, expanded)
end

function M.toggle_all_active(prompt_bufnr)
    local picker = action_state.get_current_picker(prompt_bufnr)
    local expanded = picker._sess_expanded or {}
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
    picker._sess_expanded = expanded
    refresh_active(prompt_bufnr, expanded)
end

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
    local key = selection_key(value)
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
    local key = selection_key(value)
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
    local key = selection_key(value)
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
    local key = selection_key(value)
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
    local key = selection_key(value)
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
    local key = selection_key(value)
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
    local key = selection_key(value)

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
