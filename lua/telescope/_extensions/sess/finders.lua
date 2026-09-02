---@class Sess.TelescopSessionMetadataEntry
---@field name string
---@field cwd Sess.Cwd
---@field pinned boolean
---@field last_used_at Sess.Timestamp
---@field created_at Sess.Timestamp

---@class Sess.TelescopSessionEntry
---@field id Sess.SessionId | nil
---@field metadata Sess.TelescopSessionMetadataEntry

---@class Sess.TelescopFinderReturn
---@field value Sess.TelescopSessionEntry
---@field display string
---@field ordinal string

local finders = require("telescope.finders")
local utils = require("sess.utils")
local state = require("sess.state")

local M = {}

local function replace_char(s, pos, char)
    return s:sub(1, pos - 1) .. char .. s:sub(pos + 1)
end

---@return table
function M.generate_new_finder()
    return finders.new_table({
        results = utils.get_items(),

        ---@param entry Sess.Session | Sess.DirectoryItem
        ---@return Sess.TelescopFinderReturn
        entry_maker = function(entry)
            local is_session = entry.metadata ~= nil

            ---@type Sess.TelescopSessionEntry
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

            for _, s in pairs(state.get_active_sessions()) do
                if s.id == session.id then
                    display = replace_char(display, 2, "A")
                end
            end

            local previous_session = state.get_prev_session()
            if previous_session and session.id == previous_session.id then
                display = replace_char(display, 3, "L")
            end

            local current_session = state.get_current_session()
            if current_session and session.id == current_session.id then
                return {}
            end

            ---@type Sess.TelescopFinderReturn
            return {
                value = session,
                display = display,
                ordinal = session.metadata.name .. " " .. session.metadata.cwd,
            }
        end,
    })
end

return M
