local M = {}

local base_msg = "[sess.nvim] "

---@type table<Sess.log_level, integer>
local LOG_LEVELS = {
    debug = 0,
    info = 1,
    warn = 2,
    error = 3,
}

---@param msg string
---@param level Sess.log_level
---@return nil
local function notify(msg, level)
    local configured = require("sess.api.opts").get().log_level
    if LOG_LEVELS[configured] > LOG_LEVELS[level] then
        return
    end

    vim.notify(base_msg .. msg, vim.log.levels[string.upper(level)])
end

---@param msg string
function M.debug(msg)
    notify(msg, "debug")
end

---@param msg string
function M.info(msg)
    notify(msg, "info")
end

---@param msg string
function M.warn(msg)
    notify(msg, "warn")
end

---@param msg string
function M.error(msg)
    notify(msg, "error")
end

return M
