local M = {}

---@param session_name string | nil
---@param new_session_name string | nil
---@return nil
function M.rename_session(session_name, new_session_name)
    local utils = require("sessions.utils")

    if not session_name then
        session_name = require("sessions.commands.get").current().name
        if not session_name then
            utils.notify("Session name is empty", vim.log.levels.ERROR)
            return
        end
    end

    local convert = require("sessions.convert")
    local commands = require("sessions.commands")

    local session = commands.get.by_name(session_name)
    if not session then
        utils.notify("Session doesn't exist: " .. session_name, vim.log.levels.ERROR)
        return
    end
    local file = convert.from_path(session.path)

    if not new_session_name then
        local new_name = utils.input("Rename session (" .. session.name .. ")", session.name)
        if not new_name then
            utils.notify("Operation cancelled", vim.log.levels.INFO)
            return false
        end
        if new_name.result == "" then
            return
        end
        new_session_name = new_name.result
    end

    local from = convert.make_file_name(file, { name = session.name })
    local to = convert.make_file_name(file, { name = new_session_name })

    local ok, err_msg = os.rename(from, to)
    if not ok then
        utils.notify(err_msg or "Can't rename file", vim.log.levels.ERROR)
        return
    end

    utils.notify("Session: " .. session.name .. " -> " .. new_session_name, vim.log.levels.INFO)
end

return M
