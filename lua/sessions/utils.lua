---@class Input
---@field user_input string
---@field result string

local M = {}

---@param prompt string
---@param default_value string
---@return Input | nil
function M.input(prompt, default_value)
    local convert = require("sessions.convert")
    local default = default_value and convert.to_path(default_value) or ""
    local input = vim.fn.input(prompt .. ": ", default)
    if not input then
        return
    end
    local result = input:sub(1, -1)
    local copy = result:sub(1, -1)
    result = convert.from_path(result)
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
function M.get_last_folder_in_path(path)
    if path:sub(-1) == '/' then
        path = path:sub(1, -2)
    end
    local last = path:match(".*/(.*)")
    return last or path
end

---@param marker string
---@param name string
---@return string
function M.add_marker(marker, name)
    return marker .. "%p" .. name .. "%P"
end

---@param path string
---@return string | nil
function M.remove_marker(path)
    local colon_pos = path:find(":")
    if colon_pos then
        return ":" .. path:sub(colon_pos + 1)
    end
end

---@param value string
---@param arr string[]
---@return string | nil
function M.contains(value, arr)
    for _, v in ipairs(arr) do
        if v == value then
            return v
        end
    end
end

---@return string[]
function M.get_modified_buffers()
    local modified = {}

    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr)
            and vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
            and vim.api.nvim_get_option_value("modified", { buf = bufnr })
            and vim.api.nvim_buf_get_name(bufnr) ~= "" then
            table.insert(modified, vim.api.nvim_buf_get_name(bufnr))
        end
    end

    return modified
end

---@param msg string
---@param level number
function M.notify(msg, level)
    vim.notify("Sessions.nvim: " .. msg, level)
end

return M
