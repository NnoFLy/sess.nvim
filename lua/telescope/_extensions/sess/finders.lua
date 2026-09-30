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
    idle = "○",
    unknown = "?",
    working = "●",
}

local function pad(value, width)
    return value .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(value)))
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
---@return table[]
function M.build_active_entries(sessions, agents_by_id, expanded_by_id, current_id, focused_by_id, marks_by_id)
    expanded_by_id = expanded_by_id or {}
    marks_by_id = marks_by_id or {}
    local entries = {}
    local name_width, status_width, mark_width = 0, 0, 2
    for _, mark in pairs(marks_by_id) do
        mark_width = math.max(mark_width, vim.fn.strdisplaywidth(mark))
    end
    for _, session in ipairs(sessions or {}) do
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
        local current_marker = current_id == session.id and "● " or "○ "
        entries[#entries + 1] = {
            kind = "session",
            session_id = session.id,
            session = vim.deepcopy(session),
            expanded = expanded,
            display = (expanded and "▾ " or "▸ ")
                .. current_marker
                .. pad(mark, mark_width) .. " "
                .. session.metadata.name
                .. "  "
                .. session.metadata.cwd,
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
                    ordinal = table.concat({ session.metadata.name, session.metadata.cwd, "no agents" }, " "),
                }
            else
                for index, agent in ipairs(agents) do
                    local status = agent.status or "unknown"
                    local branch = index == #agents and "└─" or "├─"
                    local focused = focused_by_id and focused_by_id[session.id] == agent.id
                    local focus_marker = focused and ">" or " "
                    local status_symbol = status_symbols[status] or "?"
                    local info = agent.info and agent.info ~= "" and "  " .. agent.info or ""
                    entries[#entries + 1] = {
                        kind = "agent",
                        session_id = session.id,
                        agent_id = agent.id,
                        agent = vim.deepcopy(agent),
                        display = string.format(
                            "  %s %s %s %s  %s%s",
                            branch,
                            focus_marker,
                            status_symbol,
                            pad(agent.name, name_width),
                            pad(status, status_width),
                            info
                        ),
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

function M.generate_active_finder(expanded_by_id, active_expand)
    expanded_by_id = expanded_by_id or {}
    active_expand = active_expand or "current"
    local snapshot = api.active.snapshot()
    local sessions = snapshot.sessions
    for _, session in ipairs(sessions) do
        if expanded_by_id[session.id] == nil then
            expanded_by_id[session.id] = default_expanded(session.id, snapshot.current_id, active_expand)
        end
    end
    for _, diagnostic in ipairs(snapshot.diagnostics or {}) do log.warn(diagnostic) end
    local results = M.build_active_entries(
        snapshot.sessions,
        snapshot.agents_by_id,
        expanded_by_id,
        snapshot.current_id,
        snapshot.focused_by_id,
        snapshot.marks_by_id
    )
    return finders.new_table({ results = results, entry_maker = function(entry)
        return { value = entry, display = entry.display, ordinal = entry.ordinal }
    end }), results
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

local function replace_char(s, pos, char)
    return s:sub(1, pos - 1) .. char .. s:sub(pos + 1)
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

    local by_path = {}
    for _, session in ipairs(sessions) do
        by_path[path_utils.identity(session.metadata.cwd) or session.metadata.cwd] = session
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
        local display = (candidate.is_self and "./" or candidate.name) .. "  " .. candidate.path
        display = display .. (session and "  [" .. metadata.name .. "]" or "  [new session]")

        results[#results + 1] = {
            path = candidate.path,
            prompt = candidate.prompt,
            is_self = candidate.is_self,
            directory = true,
            id = session and session.id or nil,
            metadata = metadata,
            display = display,
            ordinal = candidate.prompt .. " " .. display,
        }
    end

    return finders.new_table({
        results = results,
        entry_maker = function(entry)
            return {
                value = entry,
                display = entry.display,
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

            local display = "    " .. session.metadata.name .. "  " .. session.metadata.cwd
            display = pad(mark_by_id[session.id] or "", mark_width) .. " " .. display
            if session.metadata.pinned then
                display = replace_char(display, mark_width + 2, "P")
            end

            for _, s in pairs(state.active()) do
                if s.id == session.id then
                    display = replace_char(display, mark_width + 3, "A")
                end
            end

            local previous_session = state.prev()
            if previous_session and session.id == previous_session.id then
                display = replace_char(display, mark_width + 4, "L")
            end

            local current_session = state.current()
            if current_session and session.id == current_session.id then
                return nil
            end

            ---@type Sess.TelescopeFinderReturn
            return {
                value = session,
                display = display,
                ordinal = table.concat({
                    mark_by_id[session.id] or "",
                    session.metadata.name,
                    session.metadata.cwd,
                }, " "),
            }
        end,
    })
end

return M
