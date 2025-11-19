local M = {}

local base_msg = "[sessionizer.nvim] "

---@param msg string
---@return nil
function M.debug(msg)
    vim.notify(base_msg .. msg, vim.log.levels.DEBUG)
end

---@param msg string
---@return nil
function M.info(msg)
    vim.notify(base_msg .. msg, vim.log.levels.INFO)
end

---@param msg string
---@return nil
function M.warn(msg)
    vim.notify(base_msg .. msg, vim.log.levels.WARN)
end

---@param msg string
---@return nil
function M.error(msg)
    vim.notify(base_msg .. msg, vim.log.levels.ERROR)
end

return M
