local M = {}

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local api = require("sess.api")
local log = require("sess.log")
local finders = require("telescope._extensions.sess.finders")
local layout = require("telescope._extensions.sess.layout")
local load_or_create = require("sess.ui.load_or_create")
local marks = require("sess.ui.marks")

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
    if not key or type(picker.set_selection) ~= "function" then
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
end

---@param prompt_bufnr number
---@return nil
local function refresh(prompt_bufnr, finder)
    local current_picker = action_state.get_current_picker(prompt_bufnr)
    local selected = action_state.get_selected_entry()
    local key = selection_key(selected and selected.value)
    local next_finder = finder
        or finders.generate_new_finder({
            available_width = layout.available_width(current_picker),
        })
    -- Mutations redraw the preview and rows without discarding user input.
    current_picker:refresh(next_finder, { reset_prompt = false })
    restore_selection(current_picker, next_finder, key)
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

    actions.close(prompt_bufnr)

    local ok, err, _, diagnostics
    if value.directory then
        ok, err, _, diagnostics = load_or_create.run(value.path)
    elseif value.id == nil then
        ok, err, _, diagnostics = api.session.create(value.metadata.cwd)
    else
        ok, err, _, diagnostics = api.session.load(value.id)
    end

    if not ok then
        log.error(err)
    else
        log.diagnostics(diagnostics)
    end
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

    local agent_id = value.kind == "agent" and value.agent_id
    if not agent_id then
        local _, _, focused = api.agent.focused(value.session_id)
        agent_id = focused and focused.id or nil
    end
    actions.close(prompt_bufnr)
    local ok, err, _, diagnostics = api.session.load(value.session_id)
    if not ok then
        log.error(err)
        return
    end

    log.diagnostics(diagnostics)
    if agent_id then
        local focused, focus_err, _, focus_diagnostics = api.agent.focus(value.session_id, agent_id)
        if not focused then
            log.error(focus_err)
        end
        log.diagnostics(focus_diagnostics)
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

    local ok, err, _, diagnostics = api.session.restore(value.key)
    if not ok then
        log.error(err)
        return
    end

    log.diagnostics(diagnostics)
    local picker = action_state.get_current_picker(prompt_bufnr)
    refresh(
        prompt_bufnr,
        finders.generate_deleted_finder({
            available_width = layout.available_width(picker),
        })
    )
end

function M.delete_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end

    if vim.fn.confirm("Delete session " .. value.metadata.name .. "?", "&Yes\n&No", 2) ~= 1 then
        return
    end

    local current = api.state.current()
    local deleting_current = current and current.id == value.id

    -- A current-session deletion replaces the layout, including picker windows.
    if deleting_current then
        actions.close(prompt_bufnr)
    end

    local ok, err, _, diagnostics = api.session.delete(value.id)
    if not ok then
        log.error(err)
    else
        log.diagnostics(diagnostics)
    end

    if not deleting_current then
        refresh(prompt_bufnr)
    end
end

---@param prompt_bufnr number
---@return nil
function M.unload_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end

    local current = api.state.current()
    local unloading_current = current and current.id == value.id

    -- Close before capturing the current session so picker windows aren't saved.
    if unloading_current then
        actions.close(prompt_bufnr)
    end

    local ok, err, _, diagnostics = require("sess.ui.unload")(value.id)
    if ok then
        log.diagnostics(diagnostics)
    elseif err == "unload cancelled" then
        log.info("Unload cancelled")
    else
        log.error(err)
    end

    if not unloading_current then
        refresh(prompt_bufnr)
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
    vim.ui.input({ prompt = "Mark (a-z, 0-9): " }, function(input)
        local mark, parse_err = marks.parse(input or "")
        if not mark then
            log.error(parse_err)
            return
        end
        local ok, err, _, diagnostics = marks.assign(session_id, mark)
        if not ok then
            log.error(err)
            return
        end
        log.diagnostics(diagnostics)
        if is_active then
            local picker = action_state.get_current_picker(prompt_bufnr)
            -- Force one complete snapshot after a mark mutation; subsequent
            -- status polls can reuse the refreshed mark map.
            picker._sess_active_snapshot = nil
            refresh_active(prompt_bufnr, picker._sess_expanded or {})
        else
            refresh(prompt_bufnr)
        end
    end)
end

function M.toggle_pin_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end

    local ok, err, _, diagnostics = api.session.toggle_pin(value.id)
    if not ok then
        log.error(err)
    else
        log.diagnostics(diagnostics)
    end

    refresh(prompt_bufnr)
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

    local ok, err, _, diagnostics = api.session.clear_mark(mark)
    if not ok then
        log.error(err)
    else
        log.diagnostics(diagnostics)
    end
    refresh(prompt_bufnr)
end

function M.rename_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end

    vim.ui.input({
        prompt = "Enter Session Name: ",
        default = value.metadata.name,
    }, function(name)
        if not name then
            return
        end

        name = vim.trim(name)
        if name == "" then
            return
        end

        local ok, err, _, diagnostics = api.session.rename(value.id, name)
        if not ok then
            log.error(err)
        else
            log.diagnostics(diagnostics)
        end

        refresh(prompt_bufnr)
    end)
end

return M
