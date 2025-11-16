local M = {}

---@return Session | nil
local function load_cwd_session()
    local session = require("sessions.session")
    local ses = session.get.current()
    if not ses then
        return nil
    end
    return session.load(ses)
end

---@param s Session
---@return Session | nil
local function load_by_name(s)
    local session = require("sessions.session")
    local ses = session.get.by_name(s.name)
    if not ses then
        return nil
    end
    return session.load(ses)
end

---@param s Session | nil
---@return boolean
local function load_session(s)
    local set_prev_session = require("sessions.commands.last").set_prev_session
    local session = require("sessions.session")
    local current_session = session.get.current()

    ---@type Session | nil
    local ses
    if s then
        ses = load_by_name(s)
    else
        ses = load_cwd_session()
    end

    if not ses then
        return false
    end

    if current_session and (ses.name ~= current_session.name) then
        set_prev_session(current_session)
    end

    return true
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
        return load_session()
    end

    local session = require("sessions.session")
    local ses = session.get.by_name(session_name)
    if not ses then
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

    local ok = load_session(session)
    if not ok then
        utils.notify("Can't load session: " .. session.name, vim.log.levels.ERROR)
    end

    if after_load_opts.custom then
        after_load_opts.custom()
    end

    return ok
end

return M
