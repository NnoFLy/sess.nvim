local session = require("sessionizer.session")
local logger = require("sessionizer.logger")
local commands_utils = require("sessionizer.commands._utils")
local state = require("sessionizer.state")

---@param s Session
---@param new_name string | nil
---@return boolean
return function(s, new_name)
    if not s then
        logger.error("No session found")
        return false
    end

    if s.last_used == 0 then
        logger.warn("Session was not saved. You need to save it first.")
        return false
    end

    if not new_name then
        new_name = vim.fn.input(
            "Enter Session Name: ",
            commands_utils.get_last_folder_in_path(s.name or vim.fn.getcwd())
        )
        if not new_name or new_name == "" then
            return false
        end
    end

    local all_sessions = session.get.all()
    for _, ses in pairs(all_sessions) do
        if ses.name == new_name then
            logger.error("Session already exists")
            return false
        end
    end

    local new_session = session.new(new_name, s.path)

    local ok = session.rename(s, new_session)
    if not ok then
        logger.error("Failed to rename session")
        return false
    end

    state.set_current_session(new_session)

    logger.info("Session pinned: " .. new_name)

    return true
end
