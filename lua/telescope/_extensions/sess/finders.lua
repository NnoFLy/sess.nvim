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
local items = api.items
local state = api.state

local M = {}

local function replace_char(s, pos, char)
    return s:sub(1, pos - 1) .. char .. s:sub(pos + 1)
end

---@return table
function M.generate_new_finder()
    return finders.new_table({
        results = items.get_items(),

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
                        created_at = entry.metadata.created_at
                    }
                }
            else
                session = {
                    id = nil,
                    metadata = {
                        name = entry.name,
                        cwd = entry.path,
                        pinned = entry.pinned,
                        last_used_at = 0,
                        created_at = 0
                    }
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
