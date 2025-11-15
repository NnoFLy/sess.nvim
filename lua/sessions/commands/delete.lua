local M = {}

---@param session_name string | nil
---@return nil
function M.delete_session(session_name)
    local user_input = vim.fn.input("Are you sure you want to delete session " .. session_name .. "? (y/N): ")
    if user_input ~= "y" then
        return
    end

    local utils = require("sessions.utils")
    if not session_name then
        session_name = require("sessions.commands.get").current().name
        if not session_name then
            utils.notify("Session name is empty", vim.log.levels.ERROR)
            return
        end
    end

    local commands = require("sessions.commands")
    local session = commands.get.by_name(session_name)
    if not session then
        utils.notify("Session doesn't exist: " .. session_name, vim.log.levels.ERROR)
        return
    end

    local convert = require("sessions.convert")
    local parsed_session_path = convert.from_path(session.path)

    local function del(path, s)
        local file = convert.make_file_name(path, s)
        local ok, err_msg = os.remove(file)
        if not ok then
            utils.notify(err_msg or "Can't delete file", vim.log.levels.ERROR)
        end
    end

    del(parsed_session_path)
    del(parsed_session_path, session)

    utils.notify("Session deleted: " .. session.name, vim.log.levels.INFO)
end

return M
