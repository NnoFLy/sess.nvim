local M = {}

local logger = require("sessionizer.logger")
local utils = require("sessionizer.utils")
local commands_utils = require("sessionizer.commands._utils")
local state = require("sessionizer.state")
local session = require("sessionizer.session")

---@param s Session
---@return boolean
local function load_session(s)
    local current_session = session.get.current()

    if not session.load(s) then
        return false
    end

    if current_session and (s.name ~= current_session.name) then
        state.set_prev_session(current_session)
    end

    return true
end

---@param s Session
---@param before_load_opts BeforeLoadOpts | nil
---@param after_load_opts AfterLoadOpts | nil
---@return boolean
function M.load_session(s, before_load_opts, after_load_opts)
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

    if state.is_session_loaded() then
        commands.save()
    end
    state.set_session_is_loaded(true)

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
