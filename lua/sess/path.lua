local M = {}

local function has_nul(value)
    return type(value) == "string" and value:find("\0", 1, true) ~= nil
end

---@param value unknown
---@return boolean
function M.is_absolute(value)
    if type(value) ~= "string" or value == "" or has_nul(value) then
        return false
    end

    local ok, result = pcall(vim.fn.isabsolutepath, value)

    return ok and result == 1
end

local function normalize(value)
    local ok, normalized = pcall(vim.fs.normalize, value)
    if not ok or type(normalized) ~= "string" or normalized == "" then
        return nil
    end

    return normalized
end

---@param value string
---@return string?
function M.canonical_absolute(value)
    if not M.is_absolute(value) then
        return nil
    end

    local normalized = normalize(value)
    if not normalized then
        return nil
    end

    local realpath_ok, realpath = pcall(vim.uv.fs_realpath, normalized)
    if realpath_ok and type(realpath) == "string" and realpath ~= "" then
        normalized = realpath
    end

    return normalize(normalized)
end

---@param value string
---@return string?
function M.identity(value)
    if type(value) ~= "string" or value == "" or has_nul(value) then
        return nil
    end

    local ok, absolute = pcall(vim.fn.fnamemodify, value, ":p")
    if not ok or type(absolute) ~= "string" then
        return nil
    end

    return M.canonical_absolute(absolute)
end

return M
