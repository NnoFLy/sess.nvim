local state = require("sess.state")

-- Public state is read-only; the internal owner supplies defensive copies.
return {
    current = state.get_current_session,
    prev = state.get_prev_session,
    active = state.get_active_sessions,
}
