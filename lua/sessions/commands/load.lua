local M = {}

---@param s Session | nil
---@return boolean
local function load_session(s)
    local session = require("sessions.session")
    local state = require("sessions.state")

    local current_session = session.get.current()

    ---@type Session | nil
    local ses
    if s then
        ses = session.get.by_name(s.name)
    else
        ses = current_session
    end

    if not ses then
        return false
    end

    if not session.load(ses) then
        return false
    end

    if current_session and (ses.name ~= current_session.name) then
        state.set_prev_session(current_session)
    end

    return true
end

---@param s Session | nil
---@param before_load_opts BeforeLoadOpts | nil
---@param after_load_opts AfterLoadOpts | nil
---@return boolean
function M.load_session(s, before_load_opts, after_load_opts)
    local opts = require("sessions").get_opts()

    before_load_opts = vim.tbl_deep_extend("force", opts.before_load, before_load_opts or {})
    after_load_opts = vim.tbl_deep_extend("force", opts.after_load, after_load_opts or {})

    local utils = require("sessions.utils")
    local logger = require("sessions.logger")
    local session = require("sessions.session")
    local commands_utils = require("sessions.commands._utils")
    local commands = require("sessions.commands")
    local state = require("sessions.state")

    local current_session = session.get.current()
    if s and current_session and current_session.name == s.name then
        logger.info("This session is already loaded")
        return true
    end

    local modified = commands_utils.get_modified_buffers()
    if #modified > 0 then
        if not before_load_opts.auto_save_files then
            logger.warn(
                "You have unsaved changes in the following buffers(" .. #modified .. "):\n"
                .. table.concat(modified, ", ") .. "\n\n"
                .. "Please save or close them before loading a session."
            )
            return false
        end
        vim.cmd("wall")
    end

    if state.is_session_loaded() then
        commands.save()
    end

    state.set_session_is_loaded(true)

    if not s or not s.name then
        return load_session()
    end

    if before_load_opts.auto_remove_buffers then
        utils.purge_hidden_buffers()
    end

    if before_load_opts.custom then
        before_load_opts.custom()
    end

    if not load_session(s) then
        logger.error("Can't load session: " .. s.name)
        return false
    end

    if after_load_opts.custom then
        after_load_opts.custom()
    end

    logger.info("Current session: " .. s.name)

    return true
end

return M
