local M = {}

---@param session_name string | nil
---@return nil
function M.delete_session(session_name)
    local user_input = vim.fn.input("Are you sure you want to delete session " .. session_name .. "? (y/N): ")
    if user_input ~= "y" then
        return
    end

    local session = require("sessions.session")
    local utils = require("sessions.utils")

    local ses
    if not session_name then
        ses = session.get.current()
    else
        ses = session.get.by_name(session_name)
    end

    if not ses then
        utils.notify("Session not found", vim.log.levels.ERROR)
        return
    end

    require("sessions.session").delete(ses)

    utils.notify("Session deleted: " .. ses.name, vim.log.levels.INFO)
end

return M
