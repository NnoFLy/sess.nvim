local icons = require("telescope._extensions.sess.icons")

local M = {}

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
    return vim.fn.fnamemodify(value, ":~")
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
    if value.metadata and value.metadata.pinned then
        parts[#parts + 1] = "pinned"
    end
    return table.concat(parts, " " .. icons.separator .. " ")
end

local function add_field(lines, label, value)
    lines[#lines + 1] = string.format("%-10s %s", label .. ":", value or "unavailable")
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

    local agents = context.agents
    if agents == nil then
        lines[#lines + 1] = "  unavailable"
    elseif #agents == 0 then
        lines[#lines + 1] = "  none"
    else
        for _, agent in ipairs(agents) do
            local status = agent.status or "unknown"
            local info = agent.info and agent.info ~= "" and "  " .. agent.info or ""
            lines[#lines + 1] = string.format("  %s  %-8s%s", agent.name or "unknown", status, info)
        end
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
        lines[#lines + 1] = "  Warning: " .. tostring(context.snapshot_error or "invalid session snapshot")
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

---@param value table?
---@param context table?
---@return string[]
function M.format(value, context)
    context = context or {}
    if not value then
        return { "No session selected" }
    end

    local metadata = value.metadata or {}
    local lines = {}
    add_field(lines, "Session", metadata.name or value.name or "unavailable")
    add_field(lines, "Path", path_for_display(metadata.cwd or value.path))

    if value.deleted_at or value.key then
        add_field(lines, "State", "deleted")
        add_field(lines, "Deleted", date(value.deleted_at))
        add_field(lines, "Restore key", value.key or "unavailable")
        if context.warning then
            lines[#lines + 1] = ""
            lines[#lines + 1] = "Warning: " .. context.warning
        end
        return lines
    end

    context.new = value.id == nil
    add_field(lines, "State", state_text(value, context))
    if context.mark or value.mark then
        add_field(lines, "Mark", context.mark or value.mark)
    end
    add_field(lines, "Last use", date(metadata.last_used_at))

    add_agents(lines, value, context)
    add_snapshot(lines, context)
    if context.warning then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Warning: " .. context.warning
    end
    return lines
end

local function is_deleted(value)
    return value and (value.deleted_at ~= nil or value.key ~= nil)
end

local function add_snapshot_status(context, value)
    if not value or not value.id or is_deleted(value) then
        return
    end
    local called, listed, err, result = pcall(function()
        local api = require("sess.api")
        return api.session.preview(value.id)
    end)
    if not called then
        context.snapshot_error = tostring(listed)
        context.warning = context.snapshot_error
    elseif listed and err == nil and type(result) == "table" then
        context.snapshot_status = result.snapshot_status
        context.snapshot_available = result.snapshot_available
        context.snapshot_error = result.snapshot_error
    elseif err then
        context.snapshot_error = tostring(err)
        context.warning = context.snapshot_error
    end
end

local function normalize_active_value(picker, value)
    if not value or not value.session_id then
        return value
    end

    local snapshot = picker and picker._sess_active_snapshot
    for _, session in ipairs(snapshot and snapshot.sessions or {}) do
        if session.id == value.session_id then
            return session
        end
    end
    return value.session
end

local function selected_context(picker, value, options)
    local context = vim.tbl_extend("force", options or {}, {})
    if value and value.id and picker and picker._sess_active_snapshot then
        local snapshot = picker._sess_active_snapshot
        context.agents = snapshot.agents_by_id and snapshot.agents_by_id[value.id]
        context.current = snapshot.current_id == value.id
        context.active = context.current
        for _, session in ipairs(snapshot.sessions or {}) do
            if session.id == value.id then
                context.active = true
                break
            end
        end
        context.mark = snapshot.marks_by_id and snapshot.marks_by_id[value.id]
        context.active_loading = picker._sess_active_loading == true
        context.active_stale = (snapshot.stale_by_id or {})[value.id] == true
            and not context.active_loading
        add_snapshot_status(context, value)
    else
        local called, current, active = pcall(function()
            local api = require("sess.api")
            local current_item = api.state.current()
            local active_items = api.state.active()
            local is_active = false
            for _, session in ipairs(active_items or {}) do
                is_active = is_active or session.id == value.id
            end
            return current_item and current_item.id == value.id, is_active
        end)
        if called then
            context.current = current
            context.active = active
        end
        add_snapshot_status(context, value)
        if value and value.id then
            local called_marks, listed, _, entries = pcall(function()
                local ok, err, marks = require("sess.api").session.list_marks()
                return ok, err, marks
            end)
            if called_marks and listed then
                for _, entry in ipairs(entries or {}) do
                    if entry.id == value.id and not entry.stale then
                        context.mark = context.mark and (context.mark .. " @" .. entry.mark)
                            or ("@" .. entry.mark)
                    end
                end
            end
        end
    end
    return context
end

---@param options table?
---@return table?
function M.new(options)
    options = options or {}
    local ok, result = pcall(function()
        local previewers = require("telescope.previewers")
        return previewers.new_buffer_previewer({
            title = "Session Preview",
            define_preview = function(self, entry, status)
                local ok, lines = pcall(function()
                    local value = entry and entry.value
                    local picker = status and status.picker
                    value = normalize_active_value(picker, value)
                    return M.format(value, selected_context(picker, value, options))
                end)
                if not ok then
                    lines = { "Preview unavailable", "", "Warning: " .. tostring(lines) }
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
