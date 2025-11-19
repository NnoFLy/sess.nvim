local M = {}

---@param s Session | nil
---@param new_name string | nil
---@return nil
function M.pin_session(s, new_name)
    local session = require("sessions.session")
    local logger = require("sessions.logger")
    local commands_utils = require("sessions.commands._utils")

    s = s or session.get.current()
    if not s then
        logger.error("No session found")
        return
    end

    if not new_name then
        new_name = vim.fn.input(
            "Enter Session Name: ",
            commands_utils.get_last_folder_in_path(s.name or vim.fn.getcwd())
        )
        if not new_name then
            return
        end
    end

    local new_session = session.new(new_name, s.path)

    session.rename(s, new_session)

    logger.info("Session pinned: " .. new_name)
end

return M
