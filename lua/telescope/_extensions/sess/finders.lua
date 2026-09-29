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
            if session.metadata.pinned then
                display = replace_char(display, 1, "P")
            end

            for _, s in pairs(state.active()) do
                if s.id == session.id then
                    display = replace_char(display, 2, "A")
                end
            end

            local previous_session = state.prev()
            if previous_session and session.id == previous_session.id then
                display = replace_char(display, 3, "L")
            end

            local current_session = state.current()
            if current_session and session.id == current_session.id then
                return nil
            end

            ---@type Sess.TelescopeFinderReturn
            return {
                value = session,
                display = display,
                ordinal = session.metadata.name .. " " .. session.metadata.cwd,
            }
        end,
    })
end

return M
