local log = require("sess.log")
local session = require("sess.session")
local state = require("sess.state")

---@param s Sess.Session
---@param name string?
---@return boolean, string?
return function(s, name)
    if not s then
        return false, "session is not provided"
    end

    if not name then
        name = vim.fn.input("Enter Session Name: ", s.metadata.name)
    end

    if vim.trim(name) == "" then
        return false, "session name cannot be empty"
    end

    local renamed, err = session.rename(s.id, name)
    if not renamed then
        log.error(err or "failed to rename session")
        return false, err
    end

    if state.get_current_session() and state.get_current_session().id == s.id then
        state.set_current_session(renamed)
    end

    log.info("Session renamed: " .. renamed.metadata.name)
    return true
end
