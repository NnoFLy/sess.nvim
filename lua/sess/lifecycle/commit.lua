local state = require("sess.state")

local M = {}

-- Runtime state is committed only after the editor and persistence steps have
-- succeeded. Observers run after this function returns.
function M.activate(item, outgoing)
    if outgoing then
        state.set_prev_session(outgoing)
    end

    state.set_current_session(item)
    state.add_active_session(item)
end

return M
