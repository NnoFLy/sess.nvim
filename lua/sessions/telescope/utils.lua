local M = {}

---@param items Session[]
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
            entry_maker = function(entry)
                return {
                    value = entry,
                    display = entry.name,
                    ordinal = entry.name,
                }
            end,
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

---@return Session[]
function M.get_items()
    local session = require("sessions.session")
    local commands_utils = require("sessions.commands._utils")
    local opts = require("sessions").get_opts()

    local all_sessions = session.get.all()
    local current_session = session.get.current()

    ---@type Session[]
    local items = {}
    ---@type string[]
    local paths = {}
    for _, ses in ipairs(all_sessions) do
        if current_session and current_session.path == ses.path then
            goto continue
        end

        table.insert(items, ses)
        table.insert(paths, ses.path)

        ::continue::
    end

    table.sort(items, function(a, b)
        local pa, pb = commands_utils.is_pinned(a), commands_utils.is_pinned(b)
        if pa ~= pb then
            return pa
        end
        if a.last_used ~= b.last_used then
            return a.last_used > b.last_used
        end
        if a.name ~= b.name then
            return a.name < b.name
        end
        return a.path < b.path
    end)

    for _, path in pairs(opts.paths) do
        for _, dir in ipairs(commands_utils.get_user_dirs(path)) do
            if not vim.list_contains(paths, dir) then
                table.insert(items, { name = dir, path = dir, last_used = 0 })
            end
        end
    end

    return items
end

return M
