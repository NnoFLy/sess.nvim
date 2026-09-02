local buffers = require("sess.buffers")
local log = require("sess.log")
local state = require("sess.state")
local session = require("sess.session")
local usecase = require("sess.usecase")

---@param path string | nil
---@return boolean
return function(path)
    local cwd = path or vim.fn.getcwd()
    cwd = vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p"))

    if vim.fn.isdirectory(cwd) == 0 then
        log.error("Directory does not exist: " .. cwd)
        return false
    end

    local current_session = state.get_current_session()
    if not current_session then
        current_session = usecase.do_u_wanna_save()
    end

    if current_session then
        local ok, err = session.save(current_session.id)
        if not ok then
            log.error(err or "Failed to save current session")
            return false
        end
    end

    vim.fn.chdir(cwd)
    buffers.hide_all_buffers()
    vim.cmd("edit .")

    local s, err = session.create({ cwd = cwd })
    if not s then
        log.error(err or "Failed to create session")
        return false
    end

    if current_session then
        state.set_prev_session(current_session)
    end
    state.set_current_session(s)

    log.info("Session created: " .. s.metadata.name)
    return true
end
