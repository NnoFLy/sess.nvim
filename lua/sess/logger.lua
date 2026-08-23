local M = {}

local base_msg = "[sess.nvim] "

---@type table<Sess.log_level, integer>
local LOGS_LEVELS = {
    debug = 0,
    info = 1,
    warn = 2,
    error = 3,
}

---@param msg string
---@return nil
function M.debug(msg)
    local opts = require("sess").get_opts()
    if LOGS_LEVELS[opts.log_level] > LOGS_LEVELS.debug then
        return
    end
    vim.notify(base_msg .. msg, vim.log.levels.DEBUG)
end

---@param msg string
---@return nil
function M.info(msg)
    local opts = require("sess").get_opts()
    if LOGS_LEVELS[opts.log_level] > LOGS_LEVELS.info then
        return
    end
    vim.notify(base_msg .. msg, vim.log.levels.INFO)
end

---@param msg string
---@return nil
function M.warn(msg)
    local opts = require("sess").get_opts()
    if LOGS_LEVELS[opts.log_level] > LOGS_LEVELS.warn then
        return
    end
    vim.notify(base_msg .. msg, vim.log.levels.WARN)
end

---@param msg string
---@return nil
function M.error(msg)
    local opts = require("sess").get_opts()
    if LOGS_LEVELS[opts.log_level] > LOGS_LEVELS.error then
        return
    end
    vim.notify(base_msg .. msg, vim.log.levels.ERROR)
end

return M
