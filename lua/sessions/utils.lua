local M = {}

local opts = require("sessions").get_opts()

---@return Opts
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

---@return table
function M.get_options()
    local finders = require("telescope.finders")
    local sorters = require("telescope.sorters")
    local telescope_custom_actions = require("sessions.telescope_custom_actions")

    local sessions = {}
    for session_name, _ in pairs(get_dirs()) do
        table.insert(sessions, session_name:gsub("_", " "):sub(1, -1))
    end
    table.sort(sessions)

    return {
        preview = true,
        prompt_title = opts.prompt_title,
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
---@param default_value string
---@return Input | nil
function M.input(prompt, default_value)
    local default = default_value and default_value:gsub("_", " ") or ""
    local copy, result
    vim.ui.input({ prompt = prompt .. ": ", default = default}, function(input)
        if not input then
            return nil
        end
        result = input:sub(1, -1)
        copy = result:sub(1, -1)
        result = result:gsub(" ", "_"):gsub("'", "\\'")
    end)
    if not result then
        return nil
    end
    return {
        user_input = copy,
        result = result,
    }
end

---@param path string
---@return string
function M.get_last_folder(path)
    if path:sub(-1) == '/' then
        path = path:sub(1, -2)
    end
    local last = path:match(".*/(.*)")
    return last or path
end

---@param name string
---@return string
function M.add_marker(name)
    return opts.marker .. "(" .. name .. ")"
end

---@param path string
---@return string
function M.remove_marker(path)
    local colon_pos = path:find(":")
    if colon_pos then
        return ":" .. path:sub(colon_pos + 1)
    end
    return nil
end

---@param path string
---@return string
function M.antiparse(path)
    local result = path:gsub("/", ":")
    result = result:gsub(" ", "_")
    result = result:gsub('"', '\\"')
    return result
end

---@param path string
---@return string
function M.parse(path)
    local result = path:gsub(":", "/")
    result = result:gsub("_", " ")
    result = result:gsub('\\"', '"')
    return result
end

return M
