local logger = require("sessionizer.logger")
local utils = require("sessionizer.utils")
local commands_utils = require("sessionizer.commands._utils")
local state = require("sessionizer.state")
local session = require("sessionizer.session")
local terminals = require("sessionizer.terminals")

---@param s sessionizer.Session
---@param before_load_opts sessionizer.BeforeLoadOpts | nil
---@param after_load_opts sessionizer.AfterLoadOpts | nil
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
        local terms = terminals.filter_valid_terminals(terminals.get_term_buffers())
        if #terms > 0 then
            logger.debug("Terminals captured: " .. tostring(#terms))
            state.set_terminals(current_session, terms)
            terminals.hide_term_buffers(terms)
        else
            state.set_terminals(current_session, {})
        end
        commands.save()
    end

    if before_load_opts.auto_remove_buffers then
        utils.purge_hidden_buffers()
    end

    if before_load_opts.custom then
        before_load_opts.custom()
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
    vim.g.sessionizer_current_session = new_current_session.name

    local stored_terminals = terminals.filter_valid_terminals(state.get_terminals(new_current_session))
    state.set_terminals(new_current_session, stored_terminals)
    if #stored_terminals > 0 then
        terminals.unhide_term_buffers(stored_terminals)
        logger.debug("Terminals restored: " .. tostring(#stored_terminals))
    end

    if after_load_opts.custom then
        after_load_opts.custom()
    end

    logger.info("Current session: " .. s.name)

    return true
end
