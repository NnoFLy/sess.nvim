local M = {}

local logger = require("sessionizer.logger")

---@class sessionizer.Files
---@field path string
---@field marked_path string | nil

---@param path string
---@return nil
function M.create_dir(path)
    local ok, err_msg = os.execute("mkdir -p " .. path)
    if not ok then
        logger.error(err_msg or "Can't create dir")
    end
end

---@param path string
---@return boolean
function M.mksession(path)
    local cmd = "mksession! " .. path
    local ok, _ = pcall(function() vim.cmd(cmd) end)
    if not ok then
        return false
    end
    return true
end

---@param from string
---@param to string
---@return boolean
function M.rename(from, to)
    local ok, err_msg = os.rename(from, to)
    if not ok then
        logger.error(err_msg or "Can't rename file")
        return false
    end
    return true
end

---@param file string
---@return nil
function M.delete(file)
    local ok, err_msg = os.remove(file)
    if not ok then
        logger.error(err_msg or "Can't delete file")
    end
end

return M
