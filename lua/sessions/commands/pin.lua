local M = {}

---@param session_name string | nil
---@return nil
function M.pin_session(session_name)
    local session = require("sessions.commands").get_current()
    if session and session.name then
        require("sessions.commands").rename(session.name)
        require("sessions.commands").save()
        return
    end

    local utils = require("sessions.utils")
    local save_session = require("sessions.commands").save

    if not session_name then
        local prompt = utils.input("Enter Session Name", utils.get_last_folder_in_path(vim.fn.getcwd()))
        if not prompt then
            return
        end
        session_name = prompt.result
    end

    save_session()
    local make_file_name = require("sessions.utils").make_file_name
    local file_path = utils.from_path(vim.fn.getcwd()) .. ".vim"
    local file_name = make_file_name(file_path, { name = session_name })

    os.execute("touch " .. file_name)
    vim.notify("Session pinned: " .. session_name, vim.log.levels.INFO)
end

return M
