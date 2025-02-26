local M = {}

local finders = require("telescope.finders")
local sorters = require("telescope.sorters")
local telescope_custom_actions = require("sessions.telescope_custom_actions")
local opts = require("sessions").get_opts()

local function get_dirs()
    opts.dirs = {}
    for k, _ in vim.fn.execute("!ls " .. opts.path):gmatch("[A-Za-z_.:|0-9()\"'\\-]+.vim") do
        local dir = k:gsub(":", "/"):sub(1, -5)
        if dir:match(opts.marker) then
            local session_name = dir:match("[(](.+)[)]")
            dir = dir:match(opts.marker .. "[(].+[)](.*)")

            opts.dirs[session_name] = dir
        end
    end
    return opts.dirs
end

function M.get_options()
    local sessions = {}
    for session_name, _ in pairs(get_dirs()) do
        table.insert(sessions, session_name:gsub("_", " "):sub(1, -1))
    end
    table.sort(sessions)

    return {
        preview = true,
        prompt_title = "🗃️ All sessions",
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

---@class Input
---@field user_input string
---@field result string

---@param prompt string
---@return Input | nil
function M.input(prompt)
    local input = vim.fn.input(prompt .. ": ")
    local result = input:sub(1, -1)
    if result == "" then
        return nil
    end
    local copy = result:sub(1, -1)
    result = result:gsub(" ", "_"):gsub("'", "\\'")
    return {
        user_input = copy,
        result = result,
    }
end

return M
