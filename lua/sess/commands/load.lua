local log     = require("sess.log")
local buffers = require("sess.buffers")
local state   = require("sess.state")
local session = require("sess.session")
local usecase = require("sess.usecase")

local function get_modified_buffers()
    local modified = {}

    for _, bufnr in pairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr)
            and vim.api.nvim_get_option_value("modifiable", { buf = bufnr })
            and vim.api.nvim_get_option_value("modified", { buf = bufnr })
            and vim.api.nvim_buf_get_name(bufnr) ~= "" then
            table.insert(modified, vim.api.nvim_buf_get_name(bufnr))
        end
    end

    return modified
end

---@param s Sess.Session
---@param before_load_opts Sess.BeforeLoadOpts | nil
---@param after_load_opts Sess.AfterLoadOpts | nil
---@return boolean
return function(s, before_load_opts, after_load_opts)
    if not s then
        log.error("Session is not provided")
        return false
    end

    local commands = require("sess.commands")
    local opts = require("sess").get_opts()

    before_load_opts = vim.tbl_deep_extend("force", opts.before_load, before_load_opts or {})
    after_load_opts = vim.tbl_deep_extend("force", opts.after_load, after_load_opts or {})

    local modified = get_modified_buffers()
    if #modified > 0 then
        if not before_load_opts.auto_save_files then
            log.warn(
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
        local saved = commands.save()
        if not saved then
            log.error("Can't load session: failed to save the current session")
            return false
        end
    end

    if current_session and current_session.id == s.id then
        log.info("Session is already loaded: " .. s.metadata.name)
        return true
    end

    if before_load_opts.auto_hide_buffers then
        buffers.hide_all_buffers()
    end

    local ok, err = session.load_session(s.id)
    if not ok then
        log.error(err)
        log.error("Can't load session: " .. s.metadata.name)
        return false
    end

    log.debug("Previous session: " .. (current_session and current_session.metadata.name or "nil"))
    if current_session and current_session.id ~= s.id then
        state.set_prev_session(current_session)
    end

    local loaded_session = session.get(s.id) or s
    state.set_current_session(loaded_session)

    if after_load_opts.custom then
        after_load_opts.custom()
    end

    log.info("Current session: " .. s.metadata.name)

    return true
end
