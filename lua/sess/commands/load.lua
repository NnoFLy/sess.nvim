local logger         = require("sess.logger")
local buffers        = require("sess.buffers")
local commands_utils = require("sess.commands._utils")
local state          = require("sess.state")
local session        = require("sess.session")
local usecase        = require("sess.usecase")

---@param s Sess.Session
---@param before_load_opts Sess.BeforeLoadOpts | nil
---@param after_load_opts Sess.AfterLoadOpts | nil
---@return boolean
return function(s, before_load_opts, after_load_opts)
    if not s then
        logger.error("Session is not provided")
        return false
    end

    if not session.get.by_path(s.path) then
        logger.error("Session was not found: " .. s.name)
        return false
    end

    local commands = require("sess.commands")
    local opts = require("sess").get_opts()

    before_load_opts = vim.tbl_deep_extend("force", opts.before_load, before_load_opts or {})
    after_load_opts = vim.tbl_deep_extend("force", opts.after_load, after_load_opts or {})

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

    if before_load_opts.custom then
        before_load_opts.custom()
    end

    local current_session = state.get_current_session()
    if not current_session then
        current_session = usecase.do_u_wanna_save()
    end

    if current_session then
        commands.save()
    end

    if before_load_opts.auto_hide_buffers then
        buffers.hide_all_buffers()
    end

    if current_session and (s.name == current_session.name) then
        logger.warn("Previous and current sessions are the same")
    end

    local new_current_session = session.load(s)
    if not new_current_session then
        logger.error("Can't load session: " .. s.name)
        return false
    end

    logger.debug("Previous session: " .. (current_session and current_session.name or "nil"))
    if current_session then
        state.set_prev_session(current_session)
    end
    state.set_current_session(new_current_session)
    vim.g.sess_current_session = new_current_session.name

    if after_load_opts.custom then
        after_load_opts.custom()
    end

    logger.info("Current session: " .. s.name)

    return true
end
