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
local search = require("telescope._extensions.sess.search")
local rows = require("sess.ui.rows")
local layout = require("telescope._extensions.sess.layout")
local icons = require("telescope._extensions.sess.icons")

local items = api.items
local state = api.state

local M = {}

local function configured_display()
    local ok, config = pcall(require, "telescope._extensions.sess.config")
    return ok and config.values.display or {}
end

local status_symbols = icons.status

local function normalized_status(status)
    return status_symbols[status] and status or "unknown"
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
    return rows.format_session_metadata(
        metadata,
        now,
        separator or icons.for_display(configured_display()).separator
    )
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
    local separator = icons.for_display(configured_display()).separator
    return string.format(
        "ACTIVE SESSIONS " .. separator .. " %d sessions " .. separator .. " %d agents",
        summary.session_count,
        summary.agent_count
    )
end

local function display_options(options)
    options = vim.deepcopy(options or {})
    if options.highlights == nil then
        options.highlights = {}
    end
    options.mode = layout.display_mode(options, options.result_width)
    options.symbols = icons.for_display(options)
    -- Compact rows retain session metadata; active agent summaries are shown
    -- only in detailed rows.
    if options.mode == "compact" then
        options.show_agent_summary = false
    end
    return options
end

local function configured_display_options()
    local ok, config = pcall(require, "telescope._extensions.sess.config")
    local options = vim.deepcopy(ok and config.values.display or {})
    -- A formatter can be used independently in tests and by integrations; a
    -- picker invocation defaults to the current editor width.
    if options.available_width == nil then
        options.available_width = vim.o.columns
    end
    if options.result_width == nil then
        options.result_width = vim.o.columns
    end
    return display_options(options)
end

local function configured_search_options()
    local ok, config = pcall(require, "telescope._extensions.sess.config")
    return vim.deepcopy(ok and config.values.search or {})
end

-- Regular and directory finders start from an inexpensive base view. Agent
-- status is hydrated through the same cancellable snapshot used by the active
-- picker, so finder construction never performs a synchronous probe.
local function hydrate_search_finder(callback, previous_snapshot, build_finder)
    return api.active.snapshot_async(function(snapshot)
        log.diagnostics(snapshot and snapshot.diagnostics)
        local finder = build_finder(snapshot and snapshot.agents_by_id or {})
        callback(finder, finder.results, snapshot)
    end, {
        marks = false,
        previous_snapshot = previous_snapshot,
    })
end

local function session_display_parts(session, opts)
    return rows.format_session_parts(session, opts)
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

    -- Telescope pads every configured item to its declared width. Omitted
    -- parts must therefore be left out of both the displayer definition and
    -- its values, or an empty part would still consume a cell.
    local rendered_parts = {}
    for _, part in ipairs(parts) do
        if layout.display_width(part.text) > 0 then
            rendered_parts[#rendered_parts + 1] = part
        end
    end
    if #rendered_parts == 0 then
        return fallback
    end

    local items = {}
    for index, part in ipairs(rendered_parts) do
        items[index] = { width = layout.display_width(part.text) }
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
        for index, part in ipairs(rendered_parts) do
            values[index] = { part.text, part.highlight }
        end
        return displayer(values)
    end
end

-- Keep regular session columns aligned in the flat picker.
function M.format_session_display(session, opts)
    return rows.format_session_display(session, opts)
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
    stale_by_id,
    search_options
)
    search_options = search_options or configured_search_options()
    local display = display_options(
        vim.tbl_deep_extend("force", configured_display_options(), display_opts or {})
    )
    return rows.build_active(
        {
            sessions = sessions,
            agents_by_id = agents_by_id or {},
            expanded = expanded_by_id or {},
            current_id = current_id,
            focused_by_id = focused_by_id or {},
            marks_by_id = marks_by_id or {},
            previous_id = previous_id,
            agents_loaded_by_id = agents_loaded_by_id,
            stale_by_id = stale_by_id,
        },
        vim.tbl_deep_extend("force", display, { sort = search_options.sort })
    )
end

local function active_finder_from_snapshot(
    snapshot,
    expanded_by_id,
    active_expand,
    previous_snapshot,
    display_opts,
    search_options
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
        display_opts,
        snapshot.agents_loaded_by_id,
        snapshot.stale_by_id,
        search_options
    )
    local finder = finders.new_table({
        results = results,
        entry_maker = function(entry)
            return {
                value = entry,
                display = highlighted_display(entry.display_parts, entry.display),
                ordinal = entry.ordinal,
                search_fields = entry.search_fields,
                active_group_fields = entry.active_group_fields,
                active_group_ordinal = entry.active_group_ordinal,
            }
        end,
    })
    return finder, results, snapshot
end

function M.generate_active_finder_from_snapshot(snapshot, expanded_by_id, active_expand, display_opts, search_options)
    expanded_by_id = expanded_by_id or {}
    active_expand = active_expand or "current"
    return active_finder_from_snapshot(snapshot, expanded_by_id, active_expand, nil, display_opts, search_options)
end

function M.generate_active_finder(expanded_by_id, active_expand, search_options)
    expanded_by_id = expanded_by_id or {}
    active_expand = active_expand or "current"
    return active_finder_from_snapshot(api.active.snapshot(), expanded_by_id, active_expand, nil, nil, search_options)
end

function M.generate_active_finder_async(
    expanded_by_id,
    active_expand,
    callback,
    previous_snapshot,
    display_opts,
    search_options,
    on_error
)
    expanded_by_id = expanded_by_id or {}
    active_expand = active_expand or "current"
    local load_marks = not (previous_snapshot and previous_snapshot.marks_loaded)
    return api.active.snapshot_async(function(snapshot)
        if previous_snapshot
            and previous_snapshot.signature
            and snapshot.signature == previous_snapshot.signature
        then
            local called, callback_err = pcall(callback, nil, nil, snapshot, true)
            if not called and on_error then
                on_error(callback_err)
            end
            return
        end

        local ok, finder, rows, built_snapshot = pcall(
            active_finder_from_snapshot,
            snapshot,
            expanded_by_id,
            active_expand,
            previous_snapshot,
            display_opts,
            search_options
        )
        if not ok then
            if on_error then
                on_error(finder)
            end
            return
        end
        local called, callback_err = pcall(callback, finder, rows, built_snapshot, false)
        if not called and on_error then
            on_error(callback_err)
        end
    end, {
        marks = load_marks,
        previous_snapshot = previous_snapshot,
        on_error = on_error,
    })
end

function M.generate_deleted_finder(display_opts, search_options)
    local ok, err, entries, diagnostics = api.session.list_deleted()
    if not ok then
        log.error(err)
    end
    for _, diagnostic in ipairs(diagnostics or {}) do
        log.warn(diagnostic)
    end
    search_options = search_options or configured_search_options()
    entries = search.sort_results(entries or {}, search_options.sort)
    local display = display_options(
        vim.tbl_deep_extend("force", configured_display_options(), display_opts or {})
    )
    local row_by_key = {}
    local semantic_rows = rows.build(
        { mode = "restore", deleted = entries },
        vim.tbl_deep_extend("force", display, { sort = search_options.sort })
    )
    for _, row in ipairs(semantic_rows) do
        row_by_key[row.key] = row
    end
    return finders.new_table({
        results = entries,
        entry_maker = function(entry)
            local row = row_by_key[rows.deleted_key(entry.id or entry.key)]
            local search_fields = row and row.search_fields or search.fields_for_session(entry)
            return {
                value = entry,
                display = row and row.display or "",
                display_parts = row and row.display_parts or {},
                search_fields = search_fields,
                ordinal = row and row.ordinal or search.ordinal(search_fields),
            }
        end,
    })
end

---@return table
function M.directory_context()
    local ok, list_err, sessions, diagnostics = api.session.list()
    if not ok then
        log.error(list_err)
    end
    sessions = sessions or {}
    for _, diagnostic in ipairs(diagnostics or {}) do
        log.warn(diagnostic)
    end

    local by_path = {}
    local name_width = 0
    for _, session in ipairs(sessions) do
        by_path[path_utils.identity(session.metadata.cwd) or session.metadata.cwd] = session
        name_width = math.max(name_width, vim.fn.strdisplaywidth(session.metadata.name))
    end

    local mark_by_id, mark_width = mark_columns()
    local active_by_id = {}
    for _, active in ipairs(state.active()) do
        active_by_id[active.id] = true
    end

    return {
        sessions = sessions,
        by_path = by_path,
        mark_by_id = mark_by_id,
        mark_width = mark_width,
        active_by_id = active_by_id,
        current = state.current(),
        previous = state.prev(),
        name_width = name_width,
    }
end

---@return table
local function build_directory_finder(prompt, display_opts, agents_by_id, cached_candidates, search_options, context)
    local candidates, err = cached_candidates, nil
    if not candidates then
        candidates, err = path.enumerate(prompt, { fuzzy = true })
        if err then
            log.error(err)
        end
    end

    context = context or M.directory_context()
    local display = display_options(
        vim.tbl_deep_extend("force", configured_display_options(), display_opts or {})
    )
    local by_path = context.by_path
    local mark_by_id = context.mark_by_id
    local mark_width = context.mark_width
    local active_by_id = context.active_by_id
    local current = context.current
    local previous = context.previous
    local name_width = context.name_width

    for _, candidate in ipairs(candidates) do
        local candidate_path = path_utils.identity(candidate.path) or candidate.path
        local session = by_path[candidate_path]
        local name = session and session.metadata.name or candidate.name
        name_width = math.max(name_width, vim.fn.strdisplaywidth(name))
    end

    local results = {}
    search_options = search_options or configured_search_options()
    agents_by_id = agents_by_id or {}
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
        local session_id = session and session.id
        local search_fields = search.fields_for_session(display_session, {
            mark = mark_by_id[session_id],
            current = current and session and current.id == session_id,
            active = session and active_by_id[session_id] == true,
            previous = previous and session and previous.id == session_id,
            agents = session and agents_by_id[session_id],
        })
        -- Directory prompts use aliases such as ./, ../, and ~/. Keep the
        -- typed form searchable alongside the canonical path used by sessions.
        search_fields.cwd = search_fields.cwd .. " " .. candidate.prompt
        results[#results + 1] = {
            path = candidate.path,
            prompt = candidate.prompt,
            is_self = candidate.is_self,
            directory = true,
            id = session and session.id or nil,
            metadata = metadata,
            display = display_parts_text(display_parts),
            display_parts = display_parts,
            search_fields = search_fields,
            ordinal = search.ordinal(search_fields),
        }
    end
    results = search.sort_results(results, search_options.sort)
    local row_by_key = {}
    local semantic_rows = rows.build(
        { mode = "directory", directories = results },
        vim.tbl_deep_extend("force", display, { sort = search_options.sort })
    )
    for _, row in ipairs(semantic_rows) do
        row_by_key[row.key] = row
    end

    return finders.new_table({
        results = results,
        entry_maker = function(entry)
            local row = row_by_key[rows.directory_key(entry.path)]
            return {
                value = entry,
                display = highlighted_display(
                    row and row.display_parts or entry.display_parts,
                    row and row.display or entry.display
                ),
                ordinal = row and row.ordinal or entry.ordinal,
                search_fields = row and row.search_fields or entry.search_fields,
            }
        end,
    })
end

function M.generate_directory_finder(prompt, display_opts, callback, previous_snapshot, search_options, context)
    local candidates, err = path.enumerate(prompt, { fuzzy = true })
    if err then
        log.error(err)
    end
    local finder = build_directory_finder(prompt, display_opts, {}, candidates, search_options, context)
    if not callback then
        return finder
    end

    local cancel = hydrate_search_finder(callback, previous_snapshot, function(agents_by_id)
        return build_directory_finder(prompt, display_opts, agents_by_id, candidates, search_options, context)
    end)
    return finder, cancel
end

function M.generate_directory_finder_async(prompt, display_opts, callback, previous_snapshot, search_options, context)
    local _, cancel = M.generate_directory_finder(
        prompt,
        display_opts,
        callback,
        previous_snapshot,
        search_options,
        context
    )
    return cancel
end

local function build_new_finder(
    display_opts,
    agents_by_id,
    cached_results,
    cached_err,
    cached_diagnostics,
    search_options
)
    local results, err, diagnostics = cached_results, cached_err, cached_diagnostics
    if not results then
        results, err, diagnostics = items.get_items()
    end
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
    local display = display_options(
        vim.tbl_deep_extend("force", configured_display_options(), display_opts or {})
    )
    local now = os.time()
    search_options = search_options or configured_search_options()
    agents_by_id = agents_by_id or {}
    for _, entry in ipairs(results) do
        entry.search_fields = search.fields_for_session({
            id = entry.id,
            metadata = entry.metadata or {
                name = entry.name,
                cwd = entry.path,
                pinned = entry.pinned,
            },
        }, {
            mark = mark_by_id[entry.id],
            current = current and entry.id == current.id,
            active = active_by_id[entry.id] == true,
            previous = previous and entry.id == previous.id,
            agents = agents_by_id[entry.id],
        })
        -- The current session is omitted from this picker, including column sizing.
        if not current or entry.id ~= current.id then
            local name = entry.metadata and entry.metadata.name or entry.name
            name_width = math.max(name_width, vim.fn.strdisplaywidth(name))
        end
    end

    results = search.sort_results(results, search_options.sort)

    -- Build semantic session rows once. The adapter below only turns those
    -- rows into Telescope entries; it does not reconstruct their hierarchy or
    -- display data.
    local row_by_id = {}
    local semantic_sessions = {}
    for _, entry in ipairs(results) do
        if entry.metadata ~= nil then
            semantic_sessions[#semantic_sessions + 1] = entry
        end
    end
    local semantic_rows = rows.build(
        {
            sessions = semantic_sessions,
            marks_by_id = mark_by_id,
            active_by_id = active_by_id,
            agents_by_id = agents_by_id,
            current_id = current and current.id,
            previous_id = previous and previous.id,
            exclude_current = true,
        },
        vim.tbl_deep_extend("force", display, { sort = search_options.sort, now = now })
    )
    for _, row in ipairs(semantic_rows) do
        row_by_id[row.session_id] = row
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
                    directory = true,
                    path = entry.path,
                    prompt = entry.prompt,
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

            local row = is_session and row_by_id[session.id] or nil
            local display_parts = row and row.display_parts
                or session_display_parts(session, {
                    active = active_by_id[session.id] == true,
                    current_id = current and current.id,
                    previous_id = previous and previous.id,
                    mark = mark_by_id[session.id],
                    mark_width = mark_width,
                    name_width = name_width,
                    session_metadata = session.id
                            and display.mode ~= "compact"
                            and display.show_metadata ~= false
                            and M.format_session_metadata(
                                session.metadata,
                                now,
                                display.symbols.separator
                            )
                        or nil,
                    display = display,
                })

            ---@type Sess.TelescopeFinderReturn
            local search_fields = row and row.search_fields
                or search.fields_for_session(session, {
                    mark = mark_by_id[session.id],
                    current = current and session.id == current.id,
                    active = active_by_id[session.id] == true,
                    previous = previous and session.id == previous.id,
                    agents = agents_by_id[session.id],
                })
            return {
                value = session,
                display = highlighted_display(display_parts, display_parts_text(display_parts)),
                display_parts = display_parts,
                search_fields = search_fields,
                ordinal = search.ordinal(search_fields),
            }
        end,
    })
end

function M.generate_new_finder(display_opts, callback, previous_snapshot, search_options)
    local cached_results, cached_err, cached_diagnostics = items.get_items()
    local finder = build_new_finder(
        display_opts,
        {},
        cached_results,
        cached_err,
        cached_diagnostics,
        search_options
    )
    if not callback then
        return finder
    end

    local cancel = hydrate_search_finder(callback, previous_snapshot, function(agents_by_id)
        return build_new_finder(
            display_opts,
            agents_by_id,
            cached_results,
            cached_err,
            cached_diagnostics,
            search_options
        )
    end)
    return finder, cancel
end

function M.generate_new_finder_async(display_opts, callback, previous_snapshot, search_options)
    local _, cancel = M.generate_new_finder(display_opts, callback, previous_snapshot, search_options)
    return cancel
end

return M
