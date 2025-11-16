local M = {}

---@param sessions_names string[]
---@param prompt_title string
---@return table
function M.get_options(sessions_names, prompt_title)
    local finders = require("telescope.finders")
    local sorters = require("telescope.sorters")
    local telescope_custom_actions = require("sessions.telescope.custom_actions")

    return {
        preview = true,
        prompt_title = prompt_title,
        finder = finders.new_table({
            results = sessions_names,
        }),
        sorter = sorters.get_generic_fuzzy_sorter(),

        attach_mappings = function(_, map)
            map({ "n", "i" }, "<CR>", telescope_custom_actions.enter)
            map("n", "dd", telescope_custom_actions.delete_session)
            map("i", "<C-d>", telescope_custom_actions.delete_session)
            map("n", "rr", telescope_custom_actions.rename_session)
            map("i", "<C-r>", telescope_custom_actions.rename_session)
            return true
        end,
    }
end

return M
