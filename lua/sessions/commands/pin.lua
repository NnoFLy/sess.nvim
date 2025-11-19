local M = {}

---@param old_name string | nil
---@param new_name string | nil
---@return nil
function M.pin_session(old_name, new_name)
    local session = require("sessions.session")
    local utils = require("sessions.utils")
    local commands_utils = require("sessions.commands._utils")

    local old_session
    if not old_name then
        old_session = session.get.current()
    else
        old_session = session.get.by_name(old_name)
    end

    if not old_session then
        utils.notify("No session found", vim.log.levels.ERROR)
        return
    end

    if not new_name then
        new_name = vim.fn.input(
            "Enter Session Name: ",
            commands_utils.get_last_folder_in_path(old_session.name or vim.fn.getcwd())
        )
        if not new_name then
            utils.notify("Cancelled", vim.log.levels.INFO)
            return
        end
    end

    local new_session = session.new(new_name, old_session.path)
    if not old_session then
        utils.notify("Session not found", vim.log.levels.ERROR)
        return
    end

    session.rename(old_session, new_session)

    utils.notify("Session pinned: " .. new_name, vim.log.levels.INFO)
end

return M
