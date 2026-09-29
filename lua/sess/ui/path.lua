local path_utils = require("sess.path")

local M = {}

local function unescape(value)
    return (value or ""):gsub("\\\\(.)", "%1")
end

local function home()
    return vim.env.HOME or vim.fn.expand("~")
end

local function expand(value)
    value = unescape(value)
    if value == "~" then
        return home()
    end
    if vim.startswith(value, "~/") then
        return vim.fs.joinpath(home(), value:sub(3))
    end
    return value
end

local function absolute(value)
    return path_utils.identity(expand(value))
end

---@param value string
---@return boolean
function M.is_path(value)
    if type(value) ~= "string" then
        return false
    end

    value = unescape(value)
    if value:find("\0", 1, true) then
        return false
    end

    return value:match("^~/") ~= nil
        or value:match("^/") ~= nil
        or value:match("^%./") ~= nil
        or value:match("^%.%./") ~= nil
end

---@param value string
---@return string?, string?
local function directory_error(value)
    local stat = vim.uv.fs_stat(value)
    if stat and stat.type ~= "directory" then
        return "not a directory: " .. value
    end
    return "directory does not exist: " .. value
end

function M.normalize_existing(value)
    if type(value) ~= "string" or vim.trim(value) == "" then
        return nil, "directory path is required"
    end

    local normalized = absolute(value)
    if vim.fn.isdirectory(normalized) == 0 then
        return nil, directory_error(normalized)
    end

    return normalized
end

local function split(value)
    local trailing_slash = value:sub(-1) == "/"
    local normalized = absolute(value)

    if trailing_slash then
        return normalized, "", true
    end

    local parent, basename = normalized:match("^(.*)/([^/]*)$")
    if not parent or parent == "" then
        parent = "/"
    end

    return parent, basename, false
end

local function prompt_prefix(value)
    if value:sub(-1) == "/" then
        return value
    end

    local prefix = value:match("^(.*)/")
    return prefix and (prefix .. "/") or ""
end

local function prompt_for_child(value, name)
    return prompt_prefix(value) .. name .. "/"
end

local function directory_entry(path, name, prompt, is_self)
    return {
        path = vim.fs.normalize(path),
        name = name,
        prompt = prompt,
        is_self = is_self == true,
    }
end

---@param input string
---@return table[], string?
function M.enumerate(input)
    if type(input) ~= "string" or not M.is_path(input) then
        return {}, "directory completion requires a path"
    end

    local value = unescape(input)
    local parent, filter, trailing_slash = split(value)
    if vim.fn.isdirectory(parent) == 0 then
        return {}, directory_error(parent)
    end

    local results = {}
    local seen = {}

    local typed_path = absolute(value)
    if vim.fn.isdirectory(typed_path) == 1 then
        local prompt = trailing_slash and value or (value .. "/")
        local entry = directory_entry(typed_path, "./", prompt, true)
        results[#results + 1] = entry
        seen[entry.path] = true
    end

    local ok, iterator = pcall(vim.fs.dir, parent)
    if not ok or type(iterator) ~= "function" then
        return {}, "cannot read directory: " .. parent
    end

    local scanned, scan_err = pcall(function()
        while true do
            local name, kind = iterator()
            if not name then
                break
            end

            local child_path = vim.fs.joinpath(parent, name)
            local is_directory = kind == "directory"
                or (kind == "link" and vim.fn.isdirectory(child_path) == 1)
            if
                is_directory
                and name ~= "."
                and name ~= ".."
                and vim.startswith(name, filter)
            then
                local normalized = vim.fs.normalize(child_path)
                if not seen[normalized] then
                    results[#results + 1] = directory_entry(
                        normalized,
                        name,
                        prompt_for_child(value, name),
                        false
                    )
                    seen[normalized] = true
                end
            end
        end
    end)
    if not scanned then
        return {}, "cannot read directory: " .. parent .. " (" .. tostring(scan_err) .. ")"
    end

    table.sort(results, function(a, b)
        if a.is_self ~= b.is_self then
            return a.is_self
        end
        return a.name:lower() < b.name:lower()
    end)

    return results
end

---@param input string
---@return string[]
function M.complete(input)
    local entries, err = M.enumerate(input)
    if err then
        return {}
    end

    local results = {}
    for _, entry in ipairs(entries) do
        results[#results + 1] = vim.fn.fnameescape(entry.prompt)
    end

    return results
end

---@param value string
---@return string
function M.unescape(value)
    return unescape(value)
end

return M
