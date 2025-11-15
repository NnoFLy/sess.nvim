local M = {}

local convert_chars = {
    ["/"] = ':',
    ["%("] = "%%p",
    ["%)"] = "%%P",
    [" "] = "_",
    ['"'] = '%%q',
}

---@param path string
---@return string
function M.from_path(path)
    local result = path
    for k, v in pairs(convert_chars) do
        result = result:gsub(k, v)
    end
    return result
end

---@param path string
---@return string
function M.to_path(path)
    local result = path
    for k, v in pairs(convert_chars) do
        result = result:gsub(v, k)
    end
    return result
end

---@param file string
---@param session Session | nil
---@return string
function M.make_file_name(file, session)
    local home = os.getenv("HOME") or "~"
    local consts = require("sessions.consts")

    if session == nil then
        local file_name = consts.path .. file
        file_name = file_name:gsub("^~", home)
        return file_name
    end

    local file_name = consts.path
        .. consts.marker
        .. M.from_path("(" .. session.name .. ")")
        .. file
    file_name = file_name:gsub("^~", home)
    return file_name
end

return M
