local M = {}

---@param session_name string
---@return nil
function M.delete_session(session_name)
    if not session_name then
        vim.notify("Session name is empty", vim.log.levels.ERROR)
        return
    end

    local make_file_name = require("sessions.utils").make_file_name
    local utils = require("sessions.utils")
    local session = utils.get_session_by_name(session_name)
    if not session then
        vim.notify("Session doesn't exist: " .. session_name, vim.log.levels.ERROR)
        return
    end

    local file = utils.from_path(vim.fn.getcwd()) .. ".vim"
    local ok, err_msg = os.remove(make_file_name(file))
    print("File to delete:", make_file_name(file))
    if not ok then
        vim.notify(err_msg or "Can't delete file", vim.log.levels.ERROR)
    end
    ok, err_msg = os.remove(make_file_name(file, session))
    print("File to delete:", make_file_name(file, session))
    if not ok then
        vim.notify(err_msg or "Can't delete file", vim.log.levels.ERROR)
        return
    end

    vim.notify("Session deleted: " .. session.name, vim.log.levels.INFO)
end

return M
