local M = {}

---@param session Session | nil
---@param opts Opts
---@return boolean
function M.try_to_attach(opts, session)
    local utils = require("sessions.utils")

    ---@return boolean
    local function attach_by_cwd()
        local str = "silent source " .. opts.path .. utils.from_path(vim.fn.getcwd()) .. ".vim"
        local ok, _ = pcall(function() vim.cmd(str) end)
        if not ok then
            return false
        end
        return true
    end

    if session == nil then
        return attach_by_cwd()
    end

    if session.name then
        local command = "find " ..
            opts.path .. " -type f -name '" .. utils.add_marker(opts._marker, utils.from_path(session.name)) .. "*'"
        local result = vim.fn.system(command)
        if result ~= "" then
            vim.cmd("silent source " .. opts.path .. utils.remove_marker(result))
            return true
        end
    elseif session.path then
        vim.cmd.cd(session.path)
        return attach_by_cwd()
    end

    return false
end

---@param session Session | nil
---@return boolean
function M._attach_session(session)
    local opts = require("sessions").get_opts()
    local get_current = require("sessions.commands").get_current
    local set_prev_session = require("sessions.commands.last").set_prev_session

    local tmp_prev_session = get_current()
    local res = M.try_to_attach(opts, session)

    if not res then
        vim.notify("Cann't found session here", vim.log.levels.ERROR)
        return false
    end

    set_prev_session(tmp_prev_session)

    return res
end

---@param session_name string | nil
---@return boolean
function M.attach_session(session_name)
    if not session_name then
        return M._attach_session()
    end

    local utils = require("sessions.utils")
    local session = utils.get_session_by_name(session_name)
    if not session then
        vim.notify("Session doesn't exist: " .. session_name, vim.log.levels.ERROR)
        return false
    end

    local get_current = require("sessions.commands").get_current
    local current_session = get_current()
    if current_session.name == session.name then
        vim.notify("Session already attached", vim.log.levels.INFO)
        return true
    end

    local ok = M._attach_session(session)
    if not ok then
        vim.notify("Session doesn't exist: " .. session, vim.log.levels.ERROR)
    end
    return ok
end

return M
