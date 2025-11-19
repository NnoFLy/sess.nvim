local finders = require("telescope.finders")
local utils = require("telescope._extensions.sessionizer.utils")

local M = {}

---@return table
function M.generate_new_finder()
    return finders.new_table({
        results = utils.get_items(),
        entry_maker = function(entry)
            return {
                value = entry,
                display = entry.name,
                ordinal = entry.name,
            }
        end,
    })
end

return M
