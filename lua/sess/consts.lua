local M = {}

---@class Sess.Consts
---@field version integer
local consts = {
    version = 1
}

function M.get_version()
    return consts.version
end

return M
