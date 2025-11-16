local M = {}

---@param old_name string | nil
---@param new_name string | nil
---@return nil
function M.pin_session(old_name, new_name)
    local session = require("sessions.session")
    local commands = require("sessions.commands")
    local utils = require("sessions.utils")

    local ok = commands.save()
    if not ok then
        utils.notify("Failed to save session", vim.log.levels.ERROR)
        return
    end

    local old_session
    if not old_name then
        old_session = session.get.current()
        if old_session and old_session.name then
            old_name = old_session.name
        else
            utils.notify("No session found", vim.log.levels.ERROR)
            return
        end
    end

    if not new_name then
        new_name = vim.fn.input("Enter Session Name: ", utils.get_last_folder_in_path(vim.fn.getcwd()))
        if not new_name then
            return
        end
    end

    local new_session = session.new(new_name)
    old_session = old_session or session.get.by_name(old_name)
    if not old_session then
        utils.notify("Session not found", vim.log.levels.ERROR)
        return
    end

    session.rename(old_session, new_session)

    utils.notify("Session pinned: " .. new_name, vim.log.levels.INFO)
end

return M
