-- Picker-independent semantic rows.
--
-- This module deliberately knows about Sess domain values and display segments,
-- but not about picker entries, buffers, mappings, or lifecycle operations.
local path = require("sess.path")
local display = require("sess.ui.display")
local icons = require("sess.ui.icons")
local search = require("sess.ui.search")

local M = {}

local function text(value)
    return value == nil and "" or tostring(value)
end

local function copy(value)
    if type(value) ~= "table" then
        return value
    end
    local ok, result = pcall(vim.deepcopy, value)
    return ok and result or value
end

local function identity(value)
    if value == nil then
        return ""
    end
    local ok, result = pcall(path.identity, text(value))
    return ok and result or text(value)
end

-- Length-prefixing avoids collisions from user-controlled names and paths.
local function part(value)
    value = text(value)
    return #value .. ":" .. value
end

--- Return a stable identity for a semantic row.
---@param kind string
---@param identity_value any
---@return string
function M.key(kind, identity_value)
    kind = text(kind)
    if type(identity_value) == "table" then
        if kind == "directory" or kind == "worktree" then
            identity_value = identity(identity_value.path or identity_value.cwd)
        elseif kind == "agent" then
            identity_value = table.concat({
                identity_value.session_id or identity_value.parent_key or "",
                identity_value.id or identity_value.agent_id or "",
            }, "\0")
        else
            identity_value = identity_value.id or identity_value.key or identity_value.name
        end
    end
    return part(kind) .. part(identity_value)
end

function M.session_key(id)
    return M.key("session", id)
end

function M.agent_key(session_id, agent_id)
    return M.key("agent", text(session_id) .. "\0" .. text(agent_id))
end

function M.directory_key(value)
    return M.key("directory", identity(value))
end

function M.deleted_key(id)
    return M.key("deleted_session", id)
end

local function display_options(options)
    options = copy(options or {})
    options.symbols = options.symbols or icons.for_display(options)
    options.highlights = options.highlights or {}
    options.ellipsis = options.ellipsis or options.symbols.ellipsis
    if options.mode == "compact" then
        options.show_agent_summary = false
    end
    return options
end

local function pad(value, width)
    value = text(value)
    return value .. string.rep(" ", math.max(0, (width or 0) - display.display_width(value)))
end

local function status(value)
    local known = { working = true, idle = true, blocked = true, done = true, unknown = true }
    value = text(value):lower()
    return known[value] and value or "unknown"
end

local function state_for_session(session, options)
    local symbols = options.symbols
    if not session.id then
        return symbols.state.new, "new"
    elseif options.current_id == session.id then
        return symbols.state.current, "current"
    elseif options.active then
        return symbols.state.active, "active"
    end
    return symbols.state.inactive, "inactive"
end

local function relative_time(timestamp, now)
    timestamp = tonumber(timestamp)
    if not timestamp or timestamp <= 0 then
        return nil
    end
    local seconds = math.max(0, (now or os.time()) - timestamp)
    if seconds < 60 then
        return "now"
    elseif seconds < 3600 then
        return string.format("%dm ago", math.floor(seconds / 60))
    elseif seconds < 86400 then
        return string.format("%dh ago", math.floor(seconds / 3600))
    elseif seconds < 604800 then
        return string.format("%dd ago", math.floor(seconds / 86400))
    elseif seconds < 2592000 then
        return string.format("%dw ago", math.floor(seconds / 604800))
    elseif seconds < 31536000 then
        return string.format("%dmo ago", math.floor(seconds / 2592000))
    end
    return string.format("%dy ago", math.floor(seconds / 31536000))
end

function M.format_session_metadata(metadata, now, separator)
    metadata = type(metadata) == "table" and metadata or {}
    return string.format(
        "last used %s %s age %s",
        relative_time(metadata.last_used_at, now) or "never",
        separator or icons.separator,
        relative_time(metadata.created_at, now) or "unknown"
    )
end

local function agent_summary(agents, loaded, stale, separator)
    if not loaded then
        return "agents: loading"
    elseif stale then
        return "agents: stale"
    end
    local counts = {}
    for _, agent in ipairs(type(agents) == "table" and agents or {}) do
        if type(agent) == "table" then
            local state = status(agent.status)
            counts[state] = (counts[state] or 0) + 1
        end
    end
    if not next(counts) then
        return "agents: 0"
    end
    local parts = { "agents:" }
    for _, state in ipairs({ "working", "idle", "blocked", "done", "unknown" }) do
        if counts[state] then
            parts[#parts + 1] = tostring(counts[state])
            parts[#parts + 1] = state
        end
    end
    if not separator then
        return table.concat(parts, " ")
    end
    local statuses = {}
    for index = 2, #parts, 2 do
        statuses[#statuses + 1] = parts[index] .. " " .. parts[index + 1]
    end
    return "agents: " .. table.concat(statuses, " " .. separator .. " ")
end

local function session_parts(session, options)
    options = display_options(options)
    local symbols, highlights = options.symbols, options.highlights
    local tree = "  "
    if options.expandable and options.expanded then
        tree = symbols.tree.expanded
    elseif options.expandable then
        tree = symbols.tree.collapsed
    end

    local marker, state_name = state_for_session(session, options)
    local marker_highlight = highlights[state_name]
    if options.show_metadata ~= false and session.id and options.previous_id == session.id then
        marker = symbols.metadata.previous
        marker_highlight = highlights.metadata or marker_highlight
    end

    local metadata = type(session.metadata) == "table" and session.metadata or {}
    local name = text(metadata.name or session.name)
    local cwd = text(metadata.cwd or session.path)
    if options.path_style == "short" then
        cwd = vim.fn.fnamemodify(cwd, ":~")
    elseif options.path_style == "relative" then
        cwd = vim.fn.fnamemodify(cwd, ":~:.")
    end
    if options.path_width then
        cwd = display.truncate_middle(cwd, options.path_width, symbols.ellipsis)
    end

    local parts = { { text = tree } }
    if
        options.show_pinned == true
        or (options.show_metadata ~= false and options.show_pinned ~= false)
    then
        local pinned = metadata.pinned == true
        parts[#parts + 1] = {
            text = pinned and (symbols.metadata.pinned .. " ") or "  ",
            highlight = pinned and highlights.metadata or nil,
        }
    end
    parts[#parts + 1] = { text = marker .. " ", highlight = marker_highlight }
    parts[#parts + 1] = {
        text = pad(options.mark, options.mark_width or 2) .. " ",
        highlight = highlights.mark,
        omit_priority = 2,
    }
    parts[#parts + 1] = {
        text = pad(name, options.name_width or 0),
        highlight = options.name_highlight or highlights.name,
        shrink_priority = 3,
        min_width = 1,
    }
    parts[#parts + 1] = { text = "  " }
    parts[#parts + 1] = {
        text = cwd,
        highlight = highlights.cwd,
        truncate = "middle",
        ellipsis = symbols.ellipsis,
        shrink_priority = 1,
        min_width = 1,
        expendable = true,
        omit_priority = options.path_width == nil and 3 or nil,
    }

    local secondary = options.session_metadata or options.agent_status
    local secondary_index
    if secondary then
        secondary_index = #parts + 1
        parts[#parts + 1] = {
            text = "  " .. text(secondary),
            highlight = options.status_highlight or highlights.metadata,
            omit_priority = options.agent_status and 4 or 3,
        }
    end
    local fit_width = options.path_width and nil or options.available_width
    local fitted = display.fit_parts(parts, fit_width)
    if fit_width and secondary_index and fitted[secondary_index].text ~= "" then
        local fitted_width = 0
        for _, part_value in ipairs(fitted) do
            fitted_width = fitted_width + display.display_width(part_value.text)
        end
        local gap = fit_width - fitted_width
        if gap > 0 then
            table.insert(fitted, secondary_index, { text = string.rep(" ", gap) })
        end
    end
    return fitted
end

local function parts_text(parts)
    local values = {}
    for _, part_value in ipairs(parts or {}) do
        values[#values + 1] = text(part_value.text)
    end
    return table.concat(values)
end

local function safe_fields(session, options)
    local ok, fields = pcall(search.fields_for_session, session, options)
    return ok and fields or {}
end

local function row_base(kind, value, options)
    local row = copy(value or {})
    row.kind = kind
    row.value = copy(value or {})
    if type(row.value) == "table" then
        row.value.kind = kind
        row.value.key = options.key
    end
    row.key = options.key
    row.parent_key = options.parent_key
    row.depth = options.depth or 0
    row.expandable = options.expandable == true
    row.expanded = options.expanded == true
    row.actions = copy(options.actions or {})
    return row
end

local function active_session_row(session, view, options, widths)
    local agents = type(view.agents_by_id) == "table" and view.agents_by_id[session.id] or {}
    if type(agents) ~= "table" then
        agents = {}
    end
    local mark = type(view.marks_by_id) == "table" and view.marks_by_id[session.id] or ""
    local current = view.current_id == session.id
    local stale = type(view.stale_by_id) == "table" and view.stale_by_id[session.id] == true
    local loaded = view.agents_loaded_by_id == nil
        or (
            type(view.agents_loaded_by_id) == "table"
            and view.agents_loaded_by_id[session.id] == true
        )
    local fields = safe_fields(session, {
        mark = mark,
        current = current,
        active = true,
        previous = view.previous_id == session.id,
        agents = agents,
    })
    local group_ordinal = search.ordinal(fields)
    local parts = session_parts(session, {
        expandable = true,
        expanded = options.expanded,
        active = true,
        current_id = view.current_id,
        previous_id = view.previous_id,
        mark = mark,
        mark_width = widths.mark,
        name_width = widths.session_name,
        show_pinned = options.show_pinned == true,
        name_highlight = current and (options.highlights.current or options.highlights.name)
            or options.highlights.active,
        status_highlight = stale and options.highlights.stale or nil,
        agent_status = options.show_agent_summary == false and nil
            or agent_summary(agents, loaded, stale, options.symbols.separator),
        show_agent_summary = options.show_agent_summary,
        show_metadata = options.show_metadata,
        available_width = options.available_width,
        symbols = options.symbols,
        highlights = options.highlights,
    })
    local row = row_base("session", session, {
        key = M.session_key(session.id),
        depth = 0,
        expandable = true,
        expanded = options.expanded,
        actions = { load = true, unload = true, focus = true },
    })
    row.session_id = session.id
    row.current = current
    row.session = session
    row.value.session_id = session.id
    row.value.current = current
    row.display_parts = parts
    row.display = parts_text(parts)
    row.search_fields = fields
    row.ordinal = group_ordinal
    row.active_group_fields = fields
    row.active_group_ordinal = group_ordinal
    return row, agents, mark, fields, group_ordinal
end

local function active_agent_row(
    session,
    agent,
    index,
    count,
    parent,
    view,
    options,
    widths,
    mark,
    group_fields,
    group_ordinal
)
    agent = type(agent) == "table" and agent or {}
    local state = status(agent.status)
    local branch = index == count and options.symbols.tree.last_branch
        or options.symbols.tree.branch
    local focused = type(view.focused_by_id) == "table"
        and view.focused_by_id[session.id] == agent.id
    local focus_marker = focused and options.symbols.focus or " "
    local indent = options.available_width and options.available_width < 40 and "" or "  "
    local info = agent.info and text(agent.info) ~= "" and "  " .. text(agent.info) or ""
    local parts = display.fit_parts({
        {
            text = indent
                .. branch
                .. " "
                .. focus_marker
                .. " "
                .. options.symbols.status[state]
                .. " ",
            highlight = focused and (options.highlights.focused or options.highlights.agent)
                or options.highlights.agent,
        },
        {
            text = pad(agent.name, widths.agent_name),
            highlight = options.highlights.agent,
            shrink_priority = 3,
            min_width = 1,
        },
        { text = "  " },
        {
            text = pad(state, widths.status),
            highlight = options.highlights[state] or options.highlights.agent,
        },
        {
            text = info,
            highlight = options.highlights.agent,
            truncate = "end",
            ellipsis = options.symbols.ellipsis,
            shrink_priority = 1,
            min_width = 0,
            expendable = true,
            omit_priority = 4,
        },
    }, options.available_width)
    local fields = safe_fields(session, {
        mark = mark,
        current = view.current_id == session.id,
        active = true,
        previous = view.previous_id == session.id,
        agents = { agent },
    })
    local row = row_base("agent", agent, {
        key = M.agent_key(session.id, agent.id or index),
        parent_key = parent.key,
        depth = 1,
        actions = { focus = true },
    })
    row.session_id = session.id
    row.current = view.current_id == session.id
    row.agent_id = agent.id
    row.agent = agent
    row.value.session_id = session.id
    row.value.agent_id = agent.id
    row.focused = focused
    row.display_parts = parts
    row.display = parts_text(parts)
    row.search_fields = fields
    row.ordinal = search.ordinal(fields)
    row.active_group_fields = group_fields
    row.active_group_ordinal = group_ordinal
    return row
end

local function terminal_fields(terminal)
    return {
        name = text(terminal.name),
        info = table.concat(
            { text(terminal.id), text(terminal.owner_id), text(terminal.owner_name) },
            " "
        ),
        status = text(terminal.execution_state)
            .. (terminal.available and " available" or " unavailable"),
    }
end

local function terminal_display_text(value)
    return (text(value):gsub("[%c]", " "))
end

local function terminal_row(terminal, parent, index, count, options)
    local fields =
        vim.tbl_extend("force", copy(parent.search_fields or {}), terminal_fields(terminal))
    local owner = parent.kind == "background_terminals"
            and (terminal.owner_name or terminal.owner_id or "unassigned")
        or nil
    local parts = display.fit_parts({
        {
            text = "  "
                .. (index == count and options.symbols.tree.last_branch or options.symbols.tree.branch)
                .. " ",
        },
        { text = terminal_display_text(terminal.name), shrink_priority = 3, min_width = 1 },
        { text = "  " .. terminal_display_text(fields.status) },
        {
            text = owner and ("  " .. terminal_display_text(owner)) or "",
            shrink_priority = 1,
            truncate = "end",
            min_width = 0,
            expendable = true,
        },
    }, options.available_width)
    local row = row_base("terminal", terminal, {
        key = M.key("terminal", terminal.id),
        parent_key = parent.key,
        depth = 1,
        actions = { focus = true },
    })
    row.terminal_id, row.value.terminal_id = terminal.id, terminal.id
    row.session_id = terminal.owner_id
    row.value.parent_key = parent.key
    row.display_parts, row.display = parts, parts_text(parts)
    row.search_fields, row.ordinal = fields, search.ordinal(fields)
    row.active_group_fields, row.active_group_ordinal =
        parent.active_group_fields, parent.active_group_ordinal
    return row
end

--- Build active sessions with agent/terminal children and a final background group.
---@param view table
---@param options table?
---@return table[], table
function M.build_active(view, options)
    view = type(view) == "table" and view or {}
    options = display_options(options)
    if options.mode == "compact" then
        options.show_agent_summary = false
    end
    local sessions = type(view.sessions) == "table" and view.sessions or {}
    local agents_by_id = type(view.agents_by_id) == "table" and view.agents_by_id or {}
    local marks = type(view.marks_by_id) == "table" and view.marks_by_id or {}
    local expanded = options.expanded or view.expanded or {}
    local sorted = search.sort_sessions(sessions, options.sort, function(session)
        return {
            mark = marks[session.id],
            current = view.current_id == session.id,
            active = true,
            previous = view.previous_id == session.id,
            agents = type(agents_by_id[session.id]) == "table" and agents_by_id[session.id] or {},
        }
    end)

    local widths = { mark = 2, session_name = 0, agent_name = 0, status = 0 }
    for _, mark in pairs(marks) do
        widths.mark = math.max(widths.mark, display.display_width(text(mark)))
    end
    for _, session in ipairs(sorted) do
        local metadata = type(session.metadata) == "table" and session.metadata or {}
        widths.session_name =
            math.max(widths.session_name, display.display_width(text(metadata.name)))
        local session_agents = type(agents_by_id[session.id]) == "table"
                and agents_by_id[session.id]
            or {}
        for _, agent in ipairs(session_agents) do
            if type(agent) == "table" then
                widths.agent_name =
                    math.max(widths.agent_name, display.display_width(text(agent.name)))
                widths.status = math.max(widths.status, display.display_width(status(agent.status)))
            end
        end
    end

    local owned, background, active, seen = {}, {}, {}, {}
    for _, session in ipairs(sorted) do
        active[session.id] = true
    end
    for _, terminal in ipairs(view.terminals or {}) do
        if
            type(terminal) == "table"
            and type(terminal.id) == "string"
            and not seen[terminal.id]
        then
            seen[terminal.id] = true
            if terminal.owner_id and active[terminal.owner_id] then
                owned[terminal.owner_id] = owned[terminal.owner_id] or {}
                table.insert(owned[terminal.owner_id], terminal)
            else
                background[#background + 1] = terminal
            end
        end
    end
    local rows = {}
    for _, session in ipairs(sorted) do
        local session_key = M.session_key(session.id)
        local is_expanded = expanded[session_key] == true or expanded[session.id] == true
        local header, agents, mark, group_fields, group_ordinal =
            active_session_row(session, view, {
                expanded = is_expanded,
                available_width = options.available_width,
                symbols = options.symbols,
                highlights = options.highlights,
                show_metadata = options.show_metadata,
                show_pinned = options.show_pinned,
            }, widths)
        local terminals = owned[session.id] or {}
        header.terminal_ids = {}
        for _, terminal in ipairs(terminals) do
            header.terminal_ids[#header.terminal_ids + 1] = terminal.id
            local fields = terminal_fields(terminal)
            group_fields.info = text(group_fields.info) .. " " .. search.ordinal(fields)
        end
        group_ordinal = search.ordinal(group_fields)
        header.active_group_ordinal, header.ordinal = group_ordinal, group_ordinal
        if #terminals > 0 then
            header.display_parts[#header.display_parts + 1] = {
                text = "  terminals: " .. #terminals .. (view.terminals_stale and " stale" or ""),
            }
            header.display_parts = display.fit_parts(header.display_parts, options.available_width)
            header.display = parts_text(header.display_parts)
        end
        rows[#rows + 1] = header
        if is_expanded then
            local valid_agents = {}
            for _, agent in ipairs(agents) do
                if type(agent) == "table" then
                    valid_agents[#valid_agents + 1] = agent
                end
            end
            for index, agent in ipairs(valid_agents) do
                rows[#rows + 1] = active_agent_row(
                    session,
                    agent,
                    index,
                    #valid_agents + #terminals,
                    header,
                    view,
                    options,
                    widths,
                    mark,
                    group_fields,
                    group_ordinal
                )
            end
            for index, terminal in ipairs(terminals) do
                rows[#rows + 1] = terminal_row(terminal, header, index, #terminals, options)
            end
        end
    end
    if #background > 0 then
        local key = M.key("background_terminals", "")
        local is_expanded = expanded[key] == true
        local header = row_base("background_terminals", {}, {
            key = key,
            expandable = true,
            expanded = is_expanded,
            actions = { expand = true },
        })
        local fields = { name = "Background terminals", info = "", _background = true }
        header.terminal_ids = {}
        for _, terminal in ipairs(background) do
            header.terminal_ids[#header.terminal_ids + 1] = terminal.id
            fields.info = fields.info .. " " .. search.ordinal(terminal_fields(terminal))
        end
        header.search_fields, header.ordinal = fields, search.ordinal(fields)
        header.active_group_fields, header.active_group_ordinal = fields, header.ordinal
        header.display_parts = display.fit_parts({
            {
                text = (
                    is_expanded and options.symbols.tree.expanded
                    or options.symbols.tree.collapsed
                )
                    .. "Background terminals ("
                    .. #background
                    .. ")"
                    .. (view.terminals_stale and " stale" or ""),
            },
        }, options.available_width)
        header.display = parts_text(header.display_parts)
        rows[#rows + 1] = header
        for index, terminal in ipairs(is_expanded and background or {}) do
            rows[#rows + 1] = terminal_row(terminal, header, index, #background, options)
        end
    end
    return rows,
        {
            count = #rows,
            session_count = #sorted,
            generation = view.generation or view.snapshot_generation,
            diagnostics = copy(view.diagnostics or {}),
        }
end

local function regular_session_row(session, view, options, widths)
    local metadata = type(session.metadata) == "table" and session.metadata or {}
    local session_agents = view.agents_by_id and view.agents_by_id[session.id]
    if type(session_agents) ~= "table" then
        session_agents = {}
    end
    local fields = safe_fields(session, {
        mark = view.marks_by_id and view.marks_by_id[session.id],
        current = view.current_id == session.id,
        active = view.active_by_id and view.active_by_id[session.id] == true,
        previous = view.previous_id == session.id,
        agents = session_agents,
    })
    local parts = session_parts(session, {
        active = view.active_by_id and view.active_by_id[session.id] == true,
        current_id = view.current_id,
        previous_id = view.previous_id,
        mark = view.marks_by_id and view.marks_by_id[session.id],
        mark_width = widths.mark,
        name_width = widths.name,
        session_metadata = session.id
                and options.mode ~= "compact"
                and options.show_metadata ~= false
                and M.format_session_metadata(metadata, options.now, options.symbols.separator)
            or nil,
        available_width = options.available_width,
        path_style = options.path_style,
        show_metadata = options.show_metadata,
        symbols = options.symbols,
        highlights = options.highlights,
    })
    local row = row_base("session", session, {
        key = M.session_key(session.id),
        expandable = false,
        actions = { load = true, unload = true, delete = true, rename = true },
    })
    row.session_id = session.id
    row.session = session
    row.display_parts = parts
    row.display = parts_text(parts)
    row.search_fields = fields
    row.ordinal = search.ordinal(fields)
    return row
end

--- Build flat rows for regular, restore, or directory views.
function M.build(view, options, expansion)
    view = type(view) == "table" and view or {}
    options = display_options(options)
    options.mode = options.mode or view.mode or "regular"
    if options.mode == "compact" then
        options.show_agent_summary = false
    end
    options.expanded = expansion or options.expanded or view.expanded or {}
    if options.mode == "active" then
        return M.build_active(view, options)
    end

    if options.mode == "restore" then
        local rows = {}
        for _, entry in ipairs(view.deleted or view.entries or {}) do
            if type(entry) == "table" then
                local metadata = type(entry.metadata) == "table" and entry.metadata or {}
                local fields = safe_fields(entry)
                local deleted_at = tonumber(entry.deleted_at)
                local deleted = deleted_at and os.date("%Y-%m-%d %H:%M", deleted_at) or "unknown"
                local parts = display.fit_parts({
                    {
                        text = text(metadata.name or entry.name),
                        shrink_priority = 3,
                        min_width = 1,
                    },
                    { text = "  " },
                    {
                        text = text(metadata.cwd or entry.path),
                        truncate = "middle",
                        ellipsis = options.symbols.ellipsis,
                        shrink_priority = 1,
                        min_width = 1,
                        expendable = true,
                    },
                    { text = "  " .. deleted, omit_priority = 5 },
                }, options.available_width)
                local row = row_base(
                    "deleted_session",
                    entry,
                    { key = M.deleted_key(entry.id or entry.key), actions = { restore = true } }
                )
                row.deleted = entry
                row.display_parts, row.display = parts, parts_text(parts)
                row.search_fields = fields
                row.ordinal = table.concat({
                    search.ordinal(fields),
                    text(entry.id),
                    text(entry.key),
                    deleted,
                }, " ")
                rows[#rows + 1] = row
            end
        end
        return search.sort_results(rows, options.sort),
            {
                count = #rows,
                generation = view.generation or view.snapshot_generation,
                diagnostics = copy(view.diagnostics or {}),
            }
    end

    if options.mode == "directory" then
        local rows = {}
        for _, entry in ipairs(view.directories or view.entries or {}) do
            if type(entry) == "table" then
                local row = row_base("directory", entry, {
                    key = M.directory_key(entry.path or entry.cwd),
                    actions = { load = true, create = true },
                })
                row.path, row.prompt, row.directory = entry.path, entry.prompt, true
                row.display_parts = entry.display_parts
                    or { { text = text(entry.name or entry.path) } }
                row.display = parts_text(row.display_parts)
                row.search_fields = entry.search_fields or safe_fields(entry)
                row.ordinal = search.ordinal(row.search_fields)
                rows[#rows + 1] = row
            end
        end
        return search.sort_results(rows, options.sort),
            {
                count = #rows,
                generation = view.generation or view.snapshot_generation,
                diagnostics = copy(view.diagnostics or {}),
            }
    end

    local sessions = view.sessions or view.entries or {}
    local rows, widths = {}, { mark = 2, name = 0 }
    for _, session in ipairs(sessions) do
        if type(session) == "table" then
            local metadata = type(session.metadata) == "table" and session.metadata or {}
            widths.name =
                math.max(widths.name, display.display_width(text(metadata.name or session.name)))
            local mark = view.marks_by_id and view.marks_by_id[session.id]
            widths.mark = math.max(widths.mark, display.display_width(text(mark)))
        end
    end
    for _, session in ipairs(sessions) do
        if
            type(session) == "table"
            and not (view.exclude_current and view.current_id == session.id)
        then
            rows[#rows + 1] = regular_session_row(session, view, options, widths)
        end
    end
    rows = search.sort_results(rows, options.sort)
    return rows,
        {
            count = #rows,
            generation = view.generation or view.snapshot_generation,
            diagnostics = copy(view.diagnostics or {}),
        }
end

M.build_rows = M.build
M.build_active_rows = M.build_active
M.display_width = display.display_width
M.fit_parts = display.fit_parts
M.truncate_middle = display.truncate_middle
M.truncate_end = display.truncate_end
M.format_session_parts = function(session, options)
    options = options or {}
    local merged = vim.tbl_deep_extend("force", options.display or {}, options)
    merged.display = nil
    merged = display_options(merged)
    return session_parts(session, merged)
end

M.format_session_display = function(session, options)
    return parts_text(M.format_session_parts(session, options))
end

return M
