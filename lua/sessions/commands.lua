local M = {}

local opts = require("sessions").get_opts()
local utils = require("sessions.utils")

---@return boolean
function M.attach_session()
    ---@type string
    local str = "silent source " .. opts.path .. vim.fn.getcwd():gsub("/", ":") .. ".vim"
    local ok, _ = pcall(function() vim.cmd(str) end)
    if not ok then
        return false
    end
    return true
end

---@return boolean
function M.save_session()
    local str = "mksession! " .. opts.path .. vim.fn.getcwd():gsub("/", ":") .. ".vim"
    local ok, _ = pcall(function() vim.cmd(str) end)
    if not ok then
        return false
    end
    return true
end

function M.create_session()
    M.save_session()
    local prompt = utils.input("Enter Session Name", utils.get_last_folder(vim.fn.getcwd()))
    if not prompt then
        return
    end

    vim.cmd(
        "silent !touch "
        .. opts.path
        .. opts.marker
        .. "\\(" .. prompt.result .. "\\)"
        .. vim.fn.getcwd():gsub("/", ":")
        .. ".vim"
    )
    print("Session created: " .. prompt.user_input)
end

function M.open_list()
    if not pcall(require, "telescope") then
        print("You need to install telescope.nvim for this command")
        return
    end
    require("sessions.telescope_custom_actions").open_sessions_list()
end

return M
