local catalog = require("sess.session")
local state = require("sess.state")

local M = {}

-- Nil means current except for load(), which owns its cwd lookup semantics.
-- Always resolve through the catalog rather than trusting caller metadata.
function M.resolve(target)
    if target == nil then
        target = state.get_current_session()
        if not target then
            return nil, "no current session"
        end
    end

    return catalog.resolve(target)
end

return M
