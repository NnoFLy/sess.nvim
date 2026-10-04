---@class Sess.TelescopeSessionMetadataEntry
---@field name string
---@field cwd Sess.Cwd
---@field pinned boolean
---@field last_used_at Sess.Timestamp
---@field created_at Sess.Timestamp

---@class Sess.TelescopeSessionEntry
---@field id Sess.SessionId | nil
---@field metadata Sess.TelescopeSessionMetadataEntry

---@class Sess.TelescopeFinderReturn
---@field value Sess.TelescopeSessionEntry
---@field display string
---@field ordinal string

local finders = require("telescope.finders")
local api = require("sess.api")
local log = require("sess.log")
local path = require("sess.ui.path")
local path_utils = require("sess.path")

local items = api.items
local state = api.state

local M = {}

local status_symbols = {
    blocked = "⚠",
    done = "✓",
    idle = "○",
    unknown = "?",
    working = "●",
}

local status_display_order = { "working", "idle", "blocked", "done", "unknown" }

local function display_width(value)
    return vim.fn.strdisplaywidth(value or "")
end

local function pad(value, width)
    value = value or ""
    return value .. string.rep(" ", math.max(0, width - display_width(value)))
end

-- Truncate at character boundaries and measure both halves in screen cells. This
-- deliberately keeps the complete value in the ordinal; it is only a display
-- concern.
local function truncate_middle(value, width)
    value = value or ""
    if width == nil or display_width(value) <= width then
        return value
    end
    if width <= 0 then
        return ""
    elseif width == 1 then
        return "…"
    end

    local chars = vim.fn.strchars(value)
    local left_width = math.floor((width - 1) / 2)
    local right_width = width - 1 - left_width
    local left_chars = chars
    while left_chars > 0 and display_width(vim.fn.strcharpart(value, 0, left_chars)) > left_width do
        left_chars = left_chars - 1
    end
    local right_chars = chars
    while right_chars > 0
        and display_width(vim.fn.strcharpart(value, chars - right_chars, right_chars)) > right_width
    do
        right_chars = right_chars - 1
    end

    local left = vim.fn.strcharpart(value, 0, left_chars)
    local right = vim.fn.strcharpart(value, chars - right_chars, right_chars)
    return left .. "…" .. right
end

local function normalized_status(status)
    return status_symbols[status] and status or "unknown"
end

local function agent_status_text(agents, loaded, stale)
    if not loaded then
        return "agents loading"
    end
    if stale then
        return "agents stale"
    end

    local counts = {}
    for _, agent in ipairs(agents or {}) do
        local status = normalized_status(agent.status)
        counts[status] = (counts[status] or 0) + 1
    end

    if next(counts) == nil then
        return "agents 0"
    end

    local parts = { "agents" }
    for _, status in ipairs(status_display_order) do
        local count = counts[status]
        if count then
            parts[#parts + 1] = tostring(count)
            parts[#parts + 1] = status
        end
    end
    return table.concat(parts, " ")
end

local function count_agents(snapshot)
    local total = 0
    local status_counts = {}
    for _, agents in pairs(snapshot.agents_by_id or {}) do
        for _, agent in ipairs(agents or {}) do
            local status = normalized_status(agent.status)
            total = total + 1
            status_counts[status] = (status_counts[status] or 0) + 1
        end
    end
    return total, status_counts
end

-- Compact dashboard counts use the same stable status order as each session
-- header. This keeps the title useful while asynchronous agent data loads.
function M.active_dashboard_summary(snapshot)
    local total, status_counts = count_agents(snapshot or {})
    local sessions = snapshot and snapshot.sessions or {}
    return {
        session_count = #sessions,
        agent_count = total,
        status_counts = status_counts,
        loading = snapshot ~= nil
            and #sessions > 0
            and (function()
                for _, session in ipairs(sessions) do
                    if not (snapshot.agents_loaded_by_id or {})[session.id] then
                        return true
                    end
                end
                return false
            end)(),
    }
end

function M.active_dashboard_title(snapshot)
    local summary = M.active_dashboard_summary(snapshot)
    return string.format(
        "ACTIVE SESSIONS · %d sessions · %d agents",
        summary.session_count,
        summary.agent_count
    )
end

local function configured_display_options()
    local ok, config = pcall(require, "telescope._extensions.sess.config")
    local options = ok and config.values.display or {}
    options = vim.deepcopy(options or {})
    if options.highlights == nil then
        options.highlights = {}
    end
    -- A formatter can be used independently in tests and by integrations; a
    -- picker invocation defaults to the current editor width.
    if options.available_width == nil then
        options.available_width = vim.o.columns
    end
    return options
end

local function path_for_display(path_value, style)
    if style == "short" then
        return vim.fn.fnamemodify(path_value, ":~")
    elseif style == "relative" then
        return vim.fn.fnamemodify(path_value, ":~:.")
    end
    return path_value
end

local function state_for_session(session, opts)
    if not session.id then
        return "+", "new"
    elseif opts.current_id == session.id then
        return "●", "current"
    elseif opts.active then
        return "○", "active"
    end
    return "·", "inactive"
end

local function session_display_parts(session, opts)
    opts = opts or {}
    local display = opts.display or {}
    local highlights = display.highlights or {}
    local tree = "  "
    if opts.expandable and opts.expanded then
        tree = "▾ "
    elseif opts.expandable then
        tree = "▸ "
    end

    local marker, state = state_for_session(session, opts)
    local name = session.metadata.name or ""
    local cwd = path_for_display(session.metadata.cwd or "", display.path_style)
    local metadata = {}
    if display.show_metadata ~= false then
        if session.metadata.pinned then
            metadata[#metadata + 1] = "[pinned]"
        end
        if session.id and opts.previous_id == session.id then
            metadata[#metadata + 1] = "[last]"
        end
        if not session.id then
            metadata[#metadata + 1] = "[new session]"
        end
    end
    if display.show_agent_summary ~= false and opts.agent_status then
        metadata[#metadata + 1] = opts.agent_status
    end

    local prefix = tree
        .. marker .. " "
        .. pad(opts.mark or "", opts.mark_width or 2) .. " "
        .. pad(name, opts.name_width or 0)
        .. "  "
    local suffix = #metadata > 0 and "  " .. table.concat(metadata, "  ") or ""
    local path_width = opts.path_width
    if path_width == nil and display.available_width then
        path_width = math.max(
            0,
            display.available_width - display_width(prefix) - display_width(suffix)
        )
    end
    cwd = truncate_middle(cwd, path_width)

    return {
        { text = tree },
        { text = marker, highlight = highlights[state] },
        { text = " " },
        { text = pad(opts.mark or "", opts.mark_width or 2), highlight = highlights.mark },
        { text = " " },
        {
            text = pad(name, opts.name_width or 0),
            highlight = opts.name_highlight or highlights.name,
        },
        { text = "  " },
        { text = cwd, highlight = highlights.cwd },
        { text = suffix, highlight = opts.status_highlight or highlights.metadata },
    }
end

local function display_parts_text(parts)
    local values = {}
    for _, part in ipairs(parts) do
        values[#values + 1] = part.text
    end
    return table.concat(values)
end

local function highlighted_display(parts, fallback)
    if type(parts) ~= "table" then
        return fallback
    end
    local ok, entry_display = pcall(require, "telescope.pickers.entry_display")
    if not ok or type(entry_display.create) ~= "function" then
        return fallback
    end

    local items = {}
    for index, part in ipairs(parts) do
        items[index] = { width = math.max(1, display_width(part.text)) }
    end
    local ok_displayer, displayer = pcall(entry_display.create, {
        separator = "",
        items = items,
    })
    if not ok_displayer then
        return fallback
    end

    return function()
        local values = {}
        for index, part in ipairs(parts) do
            values[index] = { part.text, part.highlight }
        end
        return displayer(values)
    end
end

-- Keep session columns identical without implying expansion in the flat picker.
function M.format_session_display(session, opts)
    return display_parts_text(session_display_parts(session, opts))
end

local function mark_columns()
    local ok, err, entries, diagnostics = api.session.list_marks()
    if not ok then
        log.warn(err)
    end
    log.diagnostics(diagnostics)
    local by_id, width = {}, 2
    for _, entry in ipairs(entries or {}) do
        if not entry.stale then
            local marks = by_id[entry.id]
            by_id[entry.id] = marks and (marks .. " @" .. entry.mark) or ("@" .. entry.mark)
            width = math.max(width, vim.fn.strdisplaywidth(by_id[entry.id]))
        end
    end
    return by_id, width
end

local function default_expanded(session_id, current_id, active_expand)
    if active_expand == "all" then
        return true
    elseif active_expand == "none" then
        return false
    elseif active_expand == "current" then
        return current_id == session_id
    end

    error('sess.nvim: invalid active expansion mode "' .. tostring(active_expand) .. '"')
end

---@param sessions Sess.Session[]
---@param agents_by_id table<string, Sess.Agent[]>
---@param expanded_by_id table<string, boolean>
---@param current_id string?
---@param focused_by_id table<string, string>?
---@param marks_by_id table<string, string>?
---@param previous_id string?
---@param display_opts table?
---@param agents_loaded_by_id table<string, boolean>?
---@param stale_by_id table<string, boolean>?
---@return table[]
function M.build_active_entries(
    sessions,
    agents_by_id,
    expanded_by_id,
    current_id,
    focused_by_id,
    marks_by_id,
    previous_id,
    display_opts,
    agents_loaded_by_id,
    stale_by_id
)
    expanded_by_id = expanded_by_id or {}
    marks_by_id = marks_by_id or {}
    local display = vim.tbl_deep_extend("force", configured_display_options(), display_opts or {})
    local entries = {}
    local session_name_width, name_width, status_width, mark_width = 0, 0, 0, 2
    for _, mark in pairs(marks_by_id) do
        mark_width = math.max(mark_width, vim.fn.strdisplaywidth(mark))
    end
    for _, session in ipairs(sessions or {}) do
        session_name_width = math.max(
            session_name_width,
            vim.fn.strdisplaywidth(session.metadata.name)
        )
        for _, agent in ipairs(agents_by_id[session.id] or {}) do
            name_width = math.max(name_width, vim.fn.strdisplaywidth(agent.name))
            status_width = math.max(status_width, vim.fn.strdisplaywidth(agent.status or "unknown"))
        end
    end

    for _, session in ipairs(sessions or {}) do
        local expanded = expanded_by_id[session.id] == true
        local agents = agents_by_id[session.id] or {}
        local searchable = {}
        for _, agent in ipairs(agents) do
            local status = agent.status or "unknown"
            searchable[#searchable + 1] = table.concat({
                agent.id,
                agent.name,
                agent.info or "",
                status,
            }, " ")
        end
        local mark = marks_by_id[session.id] or ""
        local current = current_id == session.id
        local stale = stale_by_id and stale_by_id[session.id] == true
        local loaded = agents_loaded_by_id == nil or agents_loaded_by_id[session.id] == true
        local session_parts = session_display_parts(session, {
            expandable = true,
            expanded = expanded,
            active = true,
            current_id = current_id,
            previous_id = previous_id,
            mark = mark,
            mark_width = mark_width,
            name_width = session_name_width,
            name_highlight = current and (display.highlights.current or display.highlights.name)
                or display.highlights.active,
            status_highlight = stale and display.highlights.stale or nil,
            agent_status = agent_status_text(agents, loaded, stale),
            display = display,
        })
        entries[#entries + 1] = {
            kind = "session",
            session_id = session.id,
            session = vim.deepcopy(session),
            expanded = expanded,
            display = display_parts_text(session_parts),
            display_parts = session_parts,
            ordinal = table.concat({
                mark,
                session.metadata.name,
                session.metadata.cwd,
                table.concat(searchable, " "),
            }, " "),
        }
        if expanded then
            if #agents == 0 then
                entries[#entries + 1] = {
                    kind = "placeholder",
                    session_id = session.id,
                    session = vim.deepcopy(session),
                    display = "  └─ no agents",
                    ordinal = table.concat(
                        { session.metadata.name, session.metadata.cwd, "no agents" },
                        " "
                    ),
                }
            else
                for index, agent in ipairs(agents) do
                    local status = normalized_status(agent.status)
                    local branch = index == #agents and "└─" or "├─"
                    local focused = focused_by_id and focused_by_id[session.id] == agent.id
                    local focus_marker = focused and ">" or " "
                    local status_symbol = status_symbols[status]
                    local info = agent.info and agent.info ~= "" and "  " .. agent.info or ""
                    local agent_highlight = display.highlights and display.highlights.agent
                    local agent_parts = {
                        {
                            text = "  "
                                .. branch
                                .. " "
                                .. focus_marker
                                .. " "
                                .. status_symbol
                                .. " ",
                            highlight = focused and (display.highlights.focused or agent_highlight)
                                or agent_highlight,
                        },
                        { text = pad(agent.name, name_width), highlight = agent_highlight },
                        { text = "  " },
                        {
                            text = pad(status, status_width),
                            highlight = display.highlights[status] or agent_highlight,
                        },
                        { text = info, highlight = agent_highlight },
                    }
                    entries[#entries + 1] = {
                        kind = "agent",
                        session_id = session.id,
                        agent_id = agent.id,
                        agent = vim.deepcopy(agent),
                        display = display_parts_text(agent_parts),
                        display_parts = agent_parts,
                        ordinal = table.concat({
                            marks_by_id[session.id] or "",
                            session.metadata.name,
                            session.metadata.cwd,
                            agent.id,
                            agent.name,
                            agent.info or "",
                            status,
                        }, " "),
                    }
                end
            end
        end
    end
    return entries
end

local function active_finder_from_snapshot(
    snapshot,
    expanded_by_id,
    active_expand,
    previous_snapshot
)
    local sessions = snapshot.sessions
    for _, session in ipairs(sessions) do
        if expanded_by_id[session.id] == nil then
            expanded_by_id[session.id] = default_expanded(
                session.id,
                snapshot.current_id,
                active_expand
            )
        end
    end
    for _, diagnostic in ipairs(snapshot.diagnostics or {}) do log.warn(diagnostic) end

    -- Status-only snapshots reuse the last complete mark map to avoid rereading
    -- the persistent mark registry.
    if previous_snapshot and not snapshot.marks_loaded then
        snapshot.marks_by_id = previous_snapshot.marks_by_id
        snapshot.marks_loaded = previous_snapshot.marks_loaded
    end

    local previous = state.prev()
    local results = M.build_active_entries(
        snapshot.sessions,
        snapshot.agents_by_id,
        expanded_by_id,
        snapshot.current_id,
        snapshot.focused_by_id,
        snapshot.marks_by_id,
        previous and previous.id or nil,
        nil,
        snapshot.agents_loaded_by_id,
        snapshot.stale_by_id
    )
    local finder = finders.new_table({
        results = results,
        entry_maker = function(entry)
            return {
                value = entry,
                display = highlighted_display(entry.display_parts, entry.display),
                ordinal = entry.ordinal,
            }
        end,
    })
    return finder, results, snapshot
end

function M.generate_active_finder_from_snapshot(snapshot, expanded_by_id, active_expand)
    expanded_by_id = expanded_by_id or {}
    active_expand = active_expand or "current"
    return active_finder_from_snapshot(snapshot, expanded_by_id, active_expand)
end

function M.generate_active_finder(expanded_by_id, active_expand)
    expanded_by_id = expanded_by_id or {}
    active_expand = active_expand or "current"
    return active_finder_from_snapshot(api.active.snapshot(), expanded_by_id, active_expand)
end

function M.generate_active_finder_async(expanded_by_id, active_expand, callback, previous_snapshot)
    expanded_by_id = expanded_by_id or {}
    active_expand = active_expand or "current"
    local load_marks = not (previous_snapshot and previous_snapshot.marks_loaded)
    return api.active.snapshot_async(function(snapshot)
        local finder, rows = active_finder_from_snapshot(
            snapshot,
            expanded_by_id,
            active_expand,
            previous_snapshot
        )
        callback(finder, rows, snapshot)
    end, {
        marks = load_marks,
        previous_snapshot = previous_snapshot,
    })
end

function M.generate_deleted_finder()
    local ok, err, entries, diagnostics = api.session.list_deleted()
    if not ok then
        log.error(err)
    end
    for _, diagnostic in ipairs(diagnostics or {}) do
        log.warn(diagnostic)
    end
    return finders.new_table({
        results = entries or {},
        entry_maker = function(entry)
            local deleted_at = os.date("%Y-%m-%d %H:%M", entry.deleted_at)
            local display = entry.metadata.name .. "  " .. entry.metadata.cwd .. "  " .. deleted_at
            return {
                value = entry,
                display = display,
                ordinal = display .. " " .. entry.id .. " " .. entry.key,
            }
        end,
    })
end

---@return table
function M.generate_directory_finder(prompt)
    local candidates, err = path.enumerate(prompt)
    if err then
        log.error(err)
    end

    local ok, list_err, sessions, diagnostics = api.session.list()
    if not ok then
        log.error(list_err)
    end
    sessions = sessions or {}
    for _, diagnostic in ipairs(diagnostics or {}) do
        log.warn(diagnostic)
    end

    local display = configured_display_options()
    local by_path = {}
    local mark_by_id, mark_width = mark_columns()
    local active_by_id = {}
    for _, active in ipairs(state.active()) do
        active_by_id[active.id] = true
    end
    local current = state.current()
    local previous = state.prev()
    local name_width = 0
    for _, session in ipairs(sessions) do
        by_path[path_utils.identity(session.metadata.cwd) or session.metadata.cwd] = session
        name_width = math.max(name_width, vim.fn.strdisplaywidth(session.metadata.name))
    end

    for _, candidate in ipairs(candidates) do
        local candidate_path = path_utils.identity(candidate.path) or candidate.path
        local session = by_path[candidate_path]
        local name = session and session.metadata.name or candidate.name
        name_width = math.max(name_width, vim.fn.strdisplaywidth(name))
    end

    local results = {}
    for _, candidate in ipairs(candidates) do
        local candidate_path = path_utils.identity(candidate.path) or candidate.path
        local session = by_path[candidate_path]
        local metadata = session and session.metadata or {
            name = candidate.name,
            cwd = candidate.path,
            pinned = false,
            last_used_at = 0,
            created_at = 0,
        }
        local display_session = {
            id = session and session.id,
            metadata = metadata,
        }
        local display_parts = session_display_parts(display_session, {
            active = session and active_by_id[session.id] == true,
            current_id = current and current.id,
            previous_id = previous and previous.id,
            mark = session and mark_by_id[session.id],
            mark_width = mark_width,
            name_width = name_width,
            display = display,
        })
        local ordinal_display = (candidate.is_self and "./" or candidate.name)
            .. "  " .. candidate.path
            .. (session and "  [" .. metadata.name .. "]" or "  [new session]")

        results[#results + 1] = {
            path = candidate.path,
            prompt = candidate.prompt,
            is_self = candidate.is_self,
            directory = true,
            id = session and session.id or nil,
            metadata = metadata,
            display = display_parts_text(display_parts),
            display_parts = display_parts,
            ordinal = table.concat({
                candidate.prompt,
                mark_by_id[session and session.id] or "",
                ordinal_display,
            }, " "),
        }
    end

    return finders.new_table({
        results = results,
        entry_maker = function(entry)
            return {
                value = entry,
                display = highlighted_display(entry.display_parts, entry.display),
                ordinal = entry.ordinal,
            }
        end,
    })
end

function M.generate_new_finder()
    local results, err, diagnostics = items.get_items()
    if err then
        log.error(err)
    end

    for _, diagnostic in ipairs(diagnostics or {}) do
        log.warn(diagnostic)
    end

    local mark_by_id, mark_width = mark_columns()
    local name_width = 0
    local current = state.current()
    local active_by_id = {}
    for _, active in ipairs(state.active()) do
        active_by_id[active.id] = true
    end
    local previous = state.prev()
    local display = configured_display_options()
    for _, entry in ipairs(results) do
        -- The current session is omitted from this picker, including column sizing.
        if not current or entry.id ~= current.id then
            local name = entry.metadata and entry.metadata.name or entry.name
            name_width = math.max(name_width, vim.fn.strdisplaywidth(name))
        end
    end

    return finders.new_table({
        results = results,

        ---@param entry Sess.Session | Sess.DirectoryItem
        ---@return Sess.TelescopeFinderReturn
        entry_maker = function(entry)
            local is_session = entry.metadata ~= nil

            ---@type Sess.TelescopeSessionEntry
            local session
            if is_session then
                session = {
                    id = entry.id,
                    metadata = {
                        name = entry.metadata.name,
                        cwd = entry.metadata.cwd,
                        pinned = entry.metadata.pinned,
                        last_used_at = entry.metadata.last_used_at,
                        created_at = entry.metadata.created_at,
                    },
                }
            else
                session = {
                    id = nil,
                    metadata = {
                        name = entry.name,
                        cwd = entry.path,
                        pinned = entry.pinned,
                        last_used_at = 0,
                        created_at = 0,
                    },
                }
            end

            if current and session.id == current.id then
                return nil
            end

            local display_parts = session_display_parts(session, {
                active = active_by_id[session.id] == true,
                current_id = current and current.id,
                previous_id = previous and previous.id,
                mark = mark_by_id[session.id],
                mark_width = mark_width,
                name_width = name_width,
                display = display,
            })

            ---@type Sess.TelescopeFinderReturn
            return {
                value = session,
                display = display_parts_text(display_parts),
                display_parts = display_parts,
                ordinal = table.concat({
                    mark_by_id[session.id] or "",
                    session.metadata.name,
                    session.metadata.cwd,
                    session.metadata.pinned and "pinned" or "",
                    previous and previous.id == session.id and "last" or "",
                }, " "),
            }
        end,
    })
end

return M
