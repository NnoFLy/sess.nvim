local M = {}

local utils = require("sessions.utils")

---@class Session
---@field name string | nil
---@field path string | nil

---@param session Session | nil
---@param opts Opts
---@return boolean
function M.try_to_attach(opts, session)
    ---@return boolean
    local function attach_by_cwd()
        local str = "silent source " .. opts.path .. utils.antiparse(vim.fn.getcwd()) .. ".vim"
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
            opts.path .. " -type f -name '" .. utils.add_marker(opts._marker, utils.antiparse(session.name)) .. "*'"
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
function M.attach_session(session)
    local opts = require("sessions").get_opts()
    local res = M.try_to_attach(opts, session)
    if not res then
        vim.notify("Cann't found session here", vim.log.levels.ERROR)
        return false
    end
    return res
end

---@return Session
M.get_current = function()
    local opts = require("sessions").get_opts()

    local session = {}
    session.path = vim.fn.getcwd()
    local result = vim.fn.system("find " .. opts.path .. " -type f -name '*)" .. utils.antiparse(session.path) .. ".vim'")
    local start_pos = result:find("FOR_MARKER%(")
    local end_pos = result:find("%):", start_pos)
    if start_pos == nil or end_pos == nil then
        return session
    end
    local name = result:sub(start_pos + 11, end_pos - 1)
    session.name = utils.parse(name)
    return session
end

---@return boolean
function M.save_session()
    local opts = require("sessions").get_opts()

    local str = "mksession! " .. opts.path .. vim.fn.getcwd():gsub("/", ":") .. ".vim"
    local ok, _ = pcall(function() vim.cmd(str) end)
    if not ok then
        return false
    end
    return true
end

function M.pin_session()
    local prompt = utils.input("Enter Session Name", utils.get_last_folder_in_path(vim.fn.getcwd()))
    if not prompt then
        return
    end
    M.save_session()
    local opts = require("sessions").get_opts()

    local file_name = (
        opts.path
        .. opts._marker
        .. "\\(" .. prompt.result .. "\\)"
        .. vim.fn.getcwd():gsub("/", ":")
        .. ".vim"
    )

    vim.cmd("silent !touch " .. file_name)
    vim.notify("Session pinned: " .. prompt.user_input, vim.log.levels.INFO)
end

function M.open_list()
    if not pcall(require, "telescope") then
        vim.notify("You need to install telescope.nvim for this command", vim.log.levels.ERROR)
        return
    end
    require("sessions.telescope.custom_actions").open_sessions_list()
end

---@type Session
local prev_session = nil

function M.set_prev_session(session)
    prev_session = session
end

function M.get_prev_session()
    return prev_session
end

function M.open_last()
    local new_session = prev_session
    local tmp_prev_session = M.get_current()
    if not M.attach_session(new_session) then
        return
    end
    M.set_prev_session(tmp_prev_session)
end

return M
