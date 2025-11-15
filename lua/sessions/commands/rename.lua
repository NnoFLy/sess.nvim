local M = {}

---@param session_name string
---@return nil
function M.rename_session(session_name)
    local utils = require("sessions.utils")

    local session = utils.get_session_by_name(session_name)
    if not session then
        vim.notify("Session doesn't exist: " .. session_name, vim.log.levels.ERROR)
        return
    end
    local file = utils.from_path(session.path)

    local new_name = utils.input("Rename session (" .. session.name .. ")", session.name)
    if not new_name then
        vim.notify("Operation cancelled", vim.log.levels.INFO)
        return false
    end

    if new_name.result == "" then
        return
    end

    local make_file_name = require("sessions.utils").make_file_name

    local from = make_file_name(file, { name = session.name })
    local to = make_file_name(file, { name = new_name.result })

    local ok, err_msg = os.rename(from, to)
    if not ok then
        vim.notify(err_msg or "Can't rename file", vim.log.levels.ERROR)
        return
    end

    vim.notify("Session: " .. session.name .. " -> " .. new_name.user_input, vim.log.levels.INFO)
end

return M
