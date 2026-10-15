local icons = require("telescope._extensions.sess.icons")

local M = {}

local DEFAULT_MAX_AGENTS = 8

local function date(value)
    if type(value) ~= "number" or value <= 0 then
        return "unknown"
    end
    local ok, result = pcall(os.date, "%Y-%m-%d %H:%M", value)
    return ok and result or "unknown"
end

local function path_for_display(value)
    if type(value) ~= "string" or value == "" then
        return "unavailable"
    end
    local ok, result = pcall(vim.fn.fnamemodify, value, ":~")
    return ok and result or value
end

local function state_text(value, context)
    local parts = {}
    if value.id == nil then
        parts[#parts + 1] = "new"
    elseif context.current or value.current then
        parts[#parts + 1] = "current"
    elseif context.active or value.active then
        parts[#parts + 1] = "active"
    else
        parts[#parts + 1] = "inactive"
    end
    if type(value.metadata) == "table" and value.metadata.pinned then
        parts[#parts + 1] = "pinned"
    end
    return table.concat(parts, " " .. icons.separator .. " ")
end

local function add_field(lines, label, value)
    lines[#lines + 1] = string.format("%-10s %s", label .. ":", value or "unavailable")
end

local function add_warning(context, warning)
    if warning == nil or warning == "" then
        return
    end
    context.warnings = context.warnings or {}
    context.warnings[#context.warnings + 1] = tostring(warning)
end

local function add_editor_summary(lines, value, context)
    if context.show_editor_summary == false then
        return
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Editor"
    local summary = context.editor_summary
    if context.new then
        lines[#lines + 1] = "  unavailable (session not created)"
    elseif type(summary) == "table" and summary.available then
        lines[#lines + 1] = "  Buffers: " .. tostring(summary.buffers)
        lines[#lines + 1] = "  Windows: " .. tostring(summary.windows)
        lines[#lines + 1] = "  Tabs: " .. tostring(summary.tabs)
    elseif type(summary) == "table" and summary.warning then
        lines[#lines + 1] = "  unavailable"
        lines[#lines + 1] = "  Warning: " .. tostring(summary.warning)
    else
        lines[#lines + 1] = "  unavailable (session is not active)"
    end
end

local function add_agents(lines, value, context)
    if context.show_agents == false then
        return
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Agents"
    if context.active_loading then
        lines[#lines + 1] = "  Loading active data" .. icons.ellipsis
        return
    end
    if context.active_stale then
        lines[#lines + 1] = "  unavailable (stale)"
        return
    end

    local agents = type(context.agents) == "table" and context.agents or nil
    if agents == nil then
        lines[#lines + 1] = "  unavailable"
        return
    end
    if #agents == 0 then
        lines[#lines + 1] = "  none"
        return
    end

    local max_agents = context.max_agents
    if type(max_agents) ~= "number" or max_agents < 1 then
        max_agents = DEFAULT_MAX_AGENTS
    end
    max_agents = math.floor(max_agents)
    local shown = math.min(#agents, max_agents)
    for index = 1, shown do
        local agent = agents[index]
        if type(agent) == "table" then
            local name = type(agent.name) == "string" and agent.name or "unknown"
            local status = type(agent.status) == "string" and agent.status or "unknown"
            local info = type(agent.info) == "string" and agent.info ~= "" and "  " .. agent.info
                or ""
            local focused = context.focused_agent_id ~= nil
                and context.focused_agent_id == agent.id
                and "  (focused)"
                or ""
            lines[#lines + 1] = string.format("  %s  %-8s%s%s", name, status, info, focused)
        else
            add_warning(context, "ignored malformed agent data")
        end
    end
    if #agents > shown then
        lines[#lines + 1] = string.format("  ... and %d more agents", #agents - shown)
    end
end

local function add_snapshot(lines, context)
    if context.show_snapshot_summary == false then
        return
    end

    lines[#lines + 1] = ""
    lines[#lines + 1] = "Stored state"
    if context.new then
        lines[#lines + 1] = "  Snapshot: none (no saved session yet)"
    elseif context.snapshot_status == "invalid" then
        lines[#lines + 1] = "  Snapshot: invalid"
        lines[#lines + 1] = "  Warning: "
            .. tostring(context.snapshot_error or "invalid session snapshot")
    elseif context.snapshot_available == true then
        lines[#lines + 1] = "  Snapshot: available"
        lines[#lines + 1] = "  Details: not inspected"
    elseif context.snapshot_error then
        lines[#lines + 1] = "  Snapshot: unavailable"
        lines[#lines + 1] = "  Warning: " .. tostring(context.snapshot_error)
    else
        lines[#lines + 1] = "  Snapshot: unavailable"
    end
end

local function action_hint(value)
    if type(value) ~= "table" then
        return "unavailable"
    end
    if value.deleted_at or value.key then
        return "Enter restores this deleted session"
    elseif value.kind == "agent" then
        return "Enter focuses this agent"
    elseif value.directory then
        return "Enter loads or creates a session for this path"
    elseif value.id == nil then
        return "Enter creates this session"
    end
    return "Enter loads this session"
end

local function add_action_hint(lines, value, context)
    if context.show_action_hint == false then
        return
    end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Action"
    lines[#lines + 1] = "  " .. tostring(context.action_hint or action_hint(value))
end

---@param value table?
---@param context table?
---@return string[]
function M.format(value, context)
    context = context or {}
    if type(value) ~= "table" then
        return { "No session selected" }
    end

    local metadata = type(value.metadata) == "table" and value.metadata or {}
    local lines = {}
    add_field(lines, "Session", metadata.name or value.name or "unavailable")
    add_field(lines, "Path", path_for_display(metadata.cwd or value.path))

    if value.deleted_at or value.key then
        add_field(lines, "State", "deleted")
        add_field(lines, "Deleted", date(value.deleted_at))
        add_field(lines, "Restore key", value.key or "unavailable")
        add_action_hint(lines, value, context)
        if context.warning then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "Warning: " .. context.warning
        end
        return lines
    end

    local is_new = value.id == nil
    local format_context = vim.tbl_extend("force", context, { new = is_new })
    add_field(lines, "State", state_text(value, format_context))
    add_field(lines, "Mark", context.mark or value.mark or "none")
    add_field(lines, "Pin", metadata.pinned and "pinned" or "not pinned")
    add_field(lines, "Last use", date(metadata.last_used_at))

    add_editor_summary(lines, value, format_context)
    add_snapshot(lines, format_context)
    add_agents(lines, value, format_context)
    add_action_hint(lines, value, format_context)
    if format_context.warning then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Warning: " .. format_context.warning
    end
    if type(format_context.warnings) == "table" then
        for _, warning in ipairs(format_context.warnings) do
            lines[#lines + 1] = "Warning: " .. tostring(warning)
        end
    end
    return lines
end

local function is_deleted(value)
    return type(value) == "table" and (value.deleted_at ~= nil or value.key ~= nil)
end

local function editor_summary(value, current, active)
    if not active or not value or not value.id then
        return nil
    end

    local called, view_or_error = pcall(function()
        -- Runtime views are defensive copies and do not source or restore a
        -- snapshot. Prefer them over capture() so a picker scratch buffer is
        -- never counted as part of the selected session.
        return require("sess.state").get_view(value.id)
    end)
    if not called then
        return { available = false, warning = tostring(view_or_error) }
    end
    if type(view_or_error) ~= "table" then
        return nil
    end

    local buffers, windows, tabs = 0, 0, 0
    local view_buffers = type(view_or_error.buffers) == "table" and view_or_error.buffers or {}
    for _ in pairs(view_buffers) do
        buffers = buffers + 1
    end
    local view_tabs = type(view_or_error.tabs) == "table" and view_or_error.tabs or {}
    for _, tab in ipairs(view_tabs) do
        if type(tab) == "table" then
            tabs = tabs + 1
            local tab_windows = type(tab.windows) == "table" and tab.windows or {}
            for _ in pairs(tab_windows) do
                windows = windows + 1
            end
            local floats = type(tab.floats) == "table" and tab.floats or {}
            windows = windows + #floats
        end
    end
    return { available = true, buffers = buffers, windows = windows, tabs = tabs }
end

local function add_snapshot_status(context, value)
    if not value or not value.id or is_deleted(value) then
        return
    end

    -- Active rows already come from a validated runtime snapshot. Avoid
    -- resolving the ID through the persistent catalog for every preview.
    if context.active then
        local called, status, snapshot_err = pcall(function()
            local storage = require("sess.storage")
            local valid, valid_err = storage.validate_id(value.id)
            if not valid then
                return "unavailable", valid_err
            end
            return storage.inspect_snapshot(value.id)
        end)
        if called then
            context.snapshot_status = status or "unavailable"
            context.snapshot_available = status == "available"
            context.snapshot_error = snapshot_err
        else
            context.snapshot_error = tostring(status)
            add_warning(context, status)
        end
        return
    end

    local called, listed, err, result, diagnostics = pcall(function()
        local api = require("sess.api")
        return api.session.preview(value.id)
    end)
    if not called then
        context.snapshot_error = tostring(listed)
        add_warning(context, listed)
    elseif listed and err == nil and type(result) == "table" then
        context.snapshot_status = result.snapshot_status
        context.snapshot_available = result.snapshot_available
        context.snapshot_error = result.snapshot_error
        if type(diagnostics) == "table" then
            for _, warning in ipairs(diagnostics) do
                add_warning(context, warning)
            end
        end
    elseif err then
        context.snapshot_error = tostring(err)
        add_warning(context, err)
    end
end

local function normalize_active_value(picker, value)
    if not value or not value.session_id then
        return value
    end

    local snapshot = picker and picker._sess_active_snapshot
    local sessions = snapshot and type(snapshot.sessions) == "table" and snapshot.sessions or {}
    for _, session in ipairs(sessions) do
        if type(session) == "table" and session.id == value.session_id then
            return session
        end
    end
    return value.session
end

local function cache_for(picker)
    if not picker then
        return nil
    end
    picker._sess_preview_cache = picker._sess_preview_cache or {}
    return picker._sess_preview_cache
end

-- Preview probes are read-only but can inspect storage, marks, and agent
-- status. Keep their result for this picker lifetime, and let picker adapters
-- explicitly invalidate it after a mutation or completed active refresh.
function M.invalidate(picker)
    if picker then
        picker._sess_preview_cache = {}
    end
end

local function selected_context(picker, value, options, raw_value)
    local context = vim.tbl_extend("force", options or {}, {})
    if not value or not value.id then
        context.action_hint = context.action_hint or action_hint(raw_value or value)
        return context
    end

    local cache = cache_for(picker)
    local cached = cache and cache[value.id]
    if cached then
        local cached_context = vim.tbl_extend("force", context, vim.deepcopy(cached))
        cached_context.action_hint = context.action_hint or action_hint(raw_value or value)
        return cached_context
    end

    local result = {}
    local snapshot = picker and picker._sess_active_snapshot
    if snapshot then
        local agents_by_id = type(snapshot.agents_by_id) == "table" and snapshot.agents_by_id or {}
        local focused_by_id = type(snapshot.focused_by_id) == "table"
            and snapshot.focused_by_id
            or {}
        result.agents = agents_by_id[value.id]
        result.focused_agent_id = focused_by_id[value.id]
        result.current = snapshot.current_id == value.id
        result.active = result.current
        local active_by_id = type(snapshot.active_by_id) == "table" and snapshot.active_by_id or {}
        result.active = result.current or active_by_id[value.id] == true
        result.active_loading = picker._sess_active_loading == true
        local stale_by_id = type(snapshot.stale_by_id) == "table" and snapshot.stale_by_id or {}
        result.active_stale = stale_by_id[value.id] == true and not result.active_loading
    else
        local called, current, active = pcall(function()
            local api = require("sess.api")
            local current_item = api.state.current()
            local active_items = api.state.active()
            local is_active = false
            local active_sessions = type(active_items) == "table" and active_items or {}
            for _, session in ipairs(active_sessions) do
                if type(session) == "table" then
                    is_active = is_active or session.id == value.id
                end
            end
            return current_item and current_item.id == value.id, is_active
        end)
        if called then
            result.current = current
            result.active = active
        else
            add_warning(result, current)
        end

        if result.active then
            local called_agents, listed, list_err, agents, diagnostics = pcall(function()
                return require("sess.api").agent.list(value.id)
            end)
            if called_agents and listed then
                result.agents = agents
                if type(diagnostics) == "table" then
                    for _, warning in ipairs(diagnostics) do
                        add_warning(result, warning)
                    end
                end
            elseif called_agents and list_err then
                add_warning(result, list_err)
            elseif not called_agents then
                add_warning(result, listed)
            end
        end

        if value.id then
            local called_marks, marks_ok, marks_err, entries, diagnostics = pcall(function()
                return require("sess.api").session.list_marks()
            end)
            if called_marks and marks_ok then
                if type(diagnostics) == "table" then
                    for _, warning in ipairs(diagnostics) do
                        add_warning(result, warning)
                    end
                end
                for _, entry in ipairs(type(entries) == "table" and entries or {}) do
                    if type(entry) == "table" and entry.id == value.id and not entry.stale then
                        result.mark = result.mark and (result.mark .. " @" .. entry.mark)
                            or ("@" .. entry.mark)
                    end
                end
            elseif called_marks and marks_err then
                add_warning(result, marks_err)
            elseif not called_marks then
                add_warning(result, marks_ok)
            end
        end
    end

    result.editor_summary = editor_summary(value, result.current, result.active)
    add_snapshot_status(result, value)
    result.action_hint = action_hint(raw_value or value)
    if cache then
        cache[value.id] = vim.deepcopy(result)
    end
    return vim.tbl_extend("force", context, result)
end

---@param options table?
---@return table?
function M.new(options)
    options = options or {}
    local last_lines
    local ok, result = pcall(function()
        local previewers = require("telescope.previewers")
        return previewers.new_buffer_previewer({
            title = "Session Preview",
            define_preview = function(self, entry, status)
                local generated, lines = pcall(function()
                    local raw_value = entry and entry.value
                    local value = normalize_active_value(status and status.picker, raw_value)
                    return M.format(
                        value,
                        selected_context(status and status.picker, value, options, raw_value)
                    )
                end)
                if generated then
                    last_lines = vim.deepcopy(lines)
                else
                    -- Keep the previous useful content visible when a fallible
                    -- probe fails; append a diagnostic rather than blanking the pane.
                    local preview_error = lines
                    lines = last_lines and vim.deepcopy(last_lines)
                        or { "Preview unavailable" }
                    lines[#lines + 1] = ""
                    lines[#lines + 1] = "Warning: " .. tostring(preview_error)
                end
                local bufnr = self.state.bufnr
                if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
                    return
                end
                vim.bo[bufnr].modifiable = true
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
                vim.bo[bufnr].modifiable = false
                vim.bo[bufnr].buftype = "nofile"
                vim.bo[bufnr].bufhidden = "wipe"
                vim.bo[bufnr].swapfile = false
            end,
        })
    end)
    if not ok then
        return nil, result
    end
    return result
end

return M
