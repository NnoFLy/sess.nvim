local M = {}

---@param items string[]
---@param prompt_title string
---@return table
function M.get_options(items, prompt_title)
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local telescope_custom_actions = require("sessions.telescope.custom_actions")

    return {
        preview = true,
        prompt_title = prompt_title,
        finder = finders.new_table({
            results = items,
        }),
        sorter = conf.generic_sorter(),

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

---@return string[]
function M.get_items()
    local session = require("sessions.session")
    local utils = require("sessions.utils")
    local opts = require("sessions").get_opts()

    local all_sessions = session.get.all()

    local items = {}
    local count = {}
    for _, ses in ipairs(all_sessions) do
        table.insert(items, ses.name)
        if ses.name ~= ses.path then
            table.insert(items, ses.path)
            count[ses.path] = (count[ses.path] or 0) + 1
        end
    end
    for _, path in pairs(opts.paths) do
        for _, dir in ipairs(utils.get_dirs(path)) do
            table.insert(items, dir)
            count[dir] = (count[dir] or 0) + 1
        end
    end

    local result = {}
    for _, value in ipairs(items) do
        if count[value] == nil or count[value] == 1 then
            table.insert(result, value)
        end
    end

    return result
end

return M
