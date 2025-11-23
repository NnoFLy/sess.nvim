local logger = require("sessionizer.logger")
local utils = require("sessionizer.utils")
local commands_utils = require("sessionizer.commands._utils")
local state = require("sessionizer.state")
local session = require("sessionizer.session")

---@param s sessionizer.Session
---@param before_load_opts sessionizer.BeforeLoadOpts | nil
---@param after_load_opts sessionizer.AfterLoadOpts | nil
---@return boolean
return function(s, before_load_opts, after_load_opts)
    if not s then
        logger.error("No session found")
        return false
    end

    local commands = require("sessionizer.commands")
    local opts = require("sessionizer").get_opts()

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

    local current_session = state.get_current_session()
    if current_session then
        commands.save()
    end

    if before_load_opts.auto_remove_buffers then
        utils.purge_hidden_buffers()
    end

    if before_load_opts.custom then
        before_load_opts.custom()
    end

    if current_session and (s.name == current_session.name) then
        logger.warn("Session is different from current session")
        return true
    end

    local new_current_session = session.load(s)
    if not new_current_session then
        logger.error("Can't load session: " .. s.name)
        return false
    end

    if current_session then
        state.set_prev_session(current_session)
    end
    state.set_current_session(new_current_session)

    if after_load_opts.custom then
        after_load_opts.custom()
    end

    logger.info("Current session: " .. s.name)

    return true
end
