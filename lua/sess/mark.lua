local M = {}

---@param value unknown
---@return boolean, string?
function M.validate(value)
    if type(value) ~= "string" or not value:match("^[a-z0-9]$") then
        return false, "mark must be one lowercase ASCII letter or digit"
    end
    return true
end

return M
