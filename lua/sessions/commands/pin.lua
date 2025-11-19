local M = {}

local session = require("sessions.session")
local logger = require("sessions.logger")
local commands_utils = require("sessions.commands._utils")

---@param s Session
---@param new_name string | nil
---@return nil
function M.pin_session(s, new_name)
    if not s then
        logger.error("No session found")
        return
    end

    if s.last_used == 0 then
        logger.warn("Session is not used")
        return
    end

    if not new_name then
        new_name = vim.fn.input(
            "Enter Session Name: ",
            commands_utils.get_last_folder_in_path(s.name or vim.fn.getcwd())
        )
        if not new_name or new_name == "" then
            return
        end
    end

    local new_session = session.new(new_name, s.path)

    session.rename(s, new_session)

    logger.info("Session pinned: " .. new_name)
end

return M
