local session = require("sess.session")
local log = require("sess.log")
local state = require("sess.state")

---@param s Sess.Session
---@return boolean, string?
return function(s)
    if not s then
        return false, "session is not provided"
    end

    local updated, err = session.toggle_pinned(s.id)
    if not updated then
        log.error(err or "failed to toggle session pin")
        return false, err
    end

    if state.get_current_session() and state.get_current_session().id == s.id then
        state.set_current_session(updated)
    end

    log.info(updated.metadata.pinned and "Session pinned: " .. updated.metadata.name or "Session unpinned: " .. updated.metadata.name)
    return true
end
