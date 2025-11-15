local M = {}

---@return nil
function M.pin_session()
    local session = require("sessions.commands").get_current()
    if session and session.name then
        require("sessions.commands").rename_session(session.name)
        require("sessions.commands").save_session()
        return
    end

    local utils = require("sessions.utils")
    local save_session = require("sessions.commands").save_session

    local prompt = utils.input("Enter Session Name", utils.get_last_folder_in_path(vim.fn.getcwd()))
    if not prompt then
        return
    end
    save_session()
    local make_file_name = require("sessions.utils").make_file_name
    local file_path = utils.from_path(vim.fn.getcwd()) .. ".vim"
    local file_name = make_file_name(file_path, { name = prompt.result })

    os.execute("touch " .. file_name)
    vim.notify("Session pinned: " .. prompt.user_input, vim.log.levels.INFO)
end

return M
