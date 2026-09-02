local finders = require("telescope.finders")
local utils = require("sess.utils")

local M = {}

---@return table
function M.generate_new_finder()
    return finders.new_table({
        results = utils.get_items(),
        entry_maker = function(entry)
            local is_session = entry.metadata ~= nil
            local name = is_session and entry.metadata.name or entry.name
            local path = is_session and entry.metadata.cwd or entry.path

            return {
                value = entry,
                display = name .. "  " .. path,
                ordinal = name .. " " .. path,
            }
        end,
    })
end

return M
