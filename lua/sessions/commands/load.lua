local M = {}

---@param consts Consts
---@param session Session | nil
---@return boolean
function M.try_to_load(consts, session)
    local utils = require("sessions.utils")
    local convert = require("sessions.convert")

    ---@return boolean
    local function load_by_cwd()
        local str = "silent source " .. consts.path .. convert.from_path(vim.fn.getcwd()) .. ".vim"
        local ok, _ = pcall(function() vim.cmd(str) end)
        if not ok then
            return false
        end
        return true
    end

    if session == nil then
        return load_by_cwd()
    end

    if session.name then
        local command = "find " ..
            consts.path .. " -type f -name '" .. utils.add_marker(consts.marker, convert.from_path(session.name)) .. "*'"
        local result = vim.fn.system(command)
        if result ~= "" then
            vim.cmd("silent source " .. consts.path .. utils.remove_marker(result))
            return true
        end
    elseif session.path then
        vim.cmd.cd(session.path)
        return load_by_cwd()
    end

    return false
end

---@param session Session | nil
---@return boolean
function M._load_session(session)
    local consts = require("sessions.consts")
    local get = require("sessions.commands").get
    local set_prev_session = require("sessions.commands.last").set_prev_session

    local tmp_prev_session = get.current()
    local res = M.try_to_load(consts, session)

    if not res then
        return false
    end

    local current_session = get.current()
    if session and session.name == current_session.name then
        set_prev_session(tmp_prev_session)
    end

    return res
end

---@param session_name string | nil
---@param before_load_opts BeforeLoadOpts | nil
---@param after_load_opts AfterLoadOpts | nil
---@return boolean
function M.load_session(session_name, before_load_opts, after_load_opts)
    local opts = require("sessions").get_opts()

    before_load_opts = vim.tbl_deep_extend("force", opts.before_load, before_load_opts or {})
    after_load_opts = vim.tbl_deep_extend("force", opts.after_load, after_load_opts or {})

    local utils = require("sessions.utils")

    local modified = utils.get_modified_buffers()
    if #modified > 0 then
        if not before_load_opts.auto_save_files then
            utils.notify(
                "You have unsaved changes in the following buffers(" .. #modified .. "):\n"
                .. table.concat(modified, ", ") .. "\n",
                vim.log.levels.WARN
            )
            utils.notify(
                "Please save or close them before loading a session.",
                vim.log.levels.WARN
            )
            return false
        end
        vim.cmd("wall")
    end

    if not session_name then
        return M._load_session()
    end

    local commands = require("sessions.commands")
    local session = commands.get.by_name(session_name)
    if not session then
        utils.notify("Session doesn't exist: " .. session_name, vim.log.levels.ERROR)
        return false
    end

    if before_load_opts.auto_save_files then
        local ok, err = pcall(function() vim.cmd("wall") end)
        if not ok then
            utils.notify("Sessions was not saved.\n" .. err,
                vim.log.levels.WARN)
            return false
        end
    end

    if before_load_opts.auto_remove_buffers then
        utils.purge_hidden_buffers()
    end

    if before_load_opts.custom then
        before_load_opts.custom()
    end

    local ok = M._load_session(session)
    if not ok then
        utils.notify("Can't load session: " .. session.name, vim.log.levels.ERROR)
    end

    if after_load_opts.custom then
        after_load_opts.custom()
    end

    return ok
end

return M
