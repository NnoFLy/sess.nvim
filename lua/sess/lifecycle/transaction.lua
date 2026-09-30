-- Compatibility facade for integrations that used the old module name. New
-- lifecycle code imports the focused operation_scope, editor_rollback, and
-- commit modules directly.
local scope = require("sess.lifecycle.operation_scope")
local rollback = require("sess.lifecycle.editor_rollback")
local commit = require("sess.lifecycle.commit")

return {
    wrap = scope.wrap,
    change = rollback.change,
    activate = commit.activate,
}
