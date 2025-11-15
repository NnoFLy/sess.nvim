local M = {}

---@type Session
local prev_session = nil

---@param session Session
---@return nil
function M.set_prev_session(session)
    prev_session = session
end

---@return Session
function M.get_prev_session()
    return prev_session
end

---@return nil
function M._open_last()
    local attach_session = require("sessions.commands").attach_session
    if not attach_session(prev_session.name) then
        return
    end
end

---@return nil
function M.open_last()
    if not prev_session or not prev_session.name then
        vim.notify("No previous session", vim.log.levels.ERROR)
        return
    end

    local save_session = require("sessions.commands").save_session
    save_session()
    vim.cmd("wa")
    vim.cmd("silent! bufdo bd")
    M._open_last()
end

return M
