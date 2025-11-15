local M = {}

---@param path string
---@param marker string
---@param prompt_title string
---@return table
function M.get_options(path, marker, prompt_title)
    local commands = require("sessions.commands")
    local finders = require("telescope.finders")
    local sorters = require("telescope.sorters")
    local telescope_custom_actions = require("sessions.telescope.custom_actions")
    local convert = require("sessions.convert")

    local sessions = {}
    local _sessions = commands.get.all(path, marker)
    for _, session in ipairs(_sessions) do
        table.insert(sessions, convert.to_path(session.name))
    end
    table.sort(sessions)

    return {
        preview = true,
        prompt_title = prompt_title,
        finder = finders.new_table({
            results = sessions,
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
