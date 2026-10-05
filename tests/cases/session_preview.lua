fixture.setup()

local preview = require("telescope._extensions.sess.preview")
local api = require("sess.api")
local session = {
    id = "session",
    metadata = {
        name = "frontend",
        cwd = "/tmp/frontend",
        pinned = true,
        last_used_at = 1737383520,
    },
    current = true,
    mark = "@a",
}

local lines = preview.format(session, {
    agents = {
        { name = "pi", status = "working", info = "reviewing UI" },
        { name = "claude", status = "idle" },
    },
    snapshot_available = true,
})
local rendered = table.concat(lines, "\n")
assert(rendered:find("Session:%s+frontend"))
assert(rendered:find("State:%s+current · pinned"))
assert(rendered:find("Mark:%s+@a"))
assert(rendered:find("pi%s+working%s+reviewing UI"))
assert(rendered:find("Snapshot:%s+available"))
assert(rendered:find("Details:%s+not inspected"))

local new_lines = preview.format({
    metadata = { name = "new", cwd = "/tmp/new" },
}, { show_agents = false })
local new_rendered = table.concat(new_lines, "\n")
assert(new_rendered:find("State:%s+new"))
assert(new_rendered:find("no saved session yet", 1, true))
assert(not new_rendered:find("Agents"))

local deleted = preview.format({
    id = "deleted",
    key = "deleted-123-1",
    deleted_at = 1737383520,
    metadata = { name = "old", cwd = "/tmp/old" },
})
local deleted_rendered = table.concat(deleted, "\n")
assert(deleted_rendered:find("State:%s+deleted"))
assert(deleted_rendered:find("Restore key:%s+deleted%-123%-1"))
assert(not deleted_rendered:find("Stored state"))

local loading = preview.format(session, { active_loading = true })
assert(table.concat(loading, "\n"):find("Loading active data", 1, true))

local unavailable = preview.format(session, {
    snapshot_error = "session file is not readable",
})
local unavailable_text = table.concat(unavailable, "\n")
assert(unavailable_text:find("Snapshot:%s+unavailable"))
assert(unavailable_text:find("session file is not readable", 1, true))

-- A readable file that is not a complete mksession envelope is corrupt, not
-- an available snapshot. Inspection must remain non-executing.
local _, _, malformed_item = api.session.create(fixture.directory("malformed-preview"), {
    name = "malformed-preview",
})
local valid_preview, valid_preview_err, valid_preview_result = api.session.preview(malformed_item.id)
assert(valid_preview and not valid_preview_err)
assert(valid_preview_result.snapshot_status == "available")
assert(require("sess.storage").write_session(malformed_item.id, "let g:malformed_preview = 1\n"))
local inspected, inspect_err, inspected_result = api.session.preview(malformed_item.id)
assert(inspected and not inspect_err)
assert(inspected_result.snapshot_status == "invalid")
assert(inspected_result.snapshot_available == false)
assert(inspected_result.snapshot_error:find("session envelope", 1, true))
local malformed_rendered = table.concat(preview.format(malformed_item, inspected_result), "\n")
assert(malformed_rendered:find("Snapshot:%s+invalid"))
assert(malformed_rendered:find("session envelope", 1, true))
assert(vim.g.malformed_preview == nil)

package.loaded["telescope.actions"] = {
    close = function() end,
}
package.loaded["telescope.actions.state"] = {}
package.loaded["telescope.finders"] = {
    new_table = function(value)
        return value
    end,
}
package.loaded["telescope.config"] = {
    values = { generic_sorter = function() end },
}
local config = require("telescope._extensions.sess.config")
assert(config.values.preview.enabled)
assert(config.values.preview.width == 0.35)
assert(not pcall(config.setup, { preview = { width = 0 } }))
assert(not pcall(config.setup, { preview = { min_width = math.huge } }))
assert(not pcall(config.setup, { preview = { min_width = -math.huge } }))
assert(not pcall(config.setup, { preview = { min_width = 0 / 0 } }))
assert(not pcall(config.setup, { preview = { show_agents = "yes" } }))
config.setup({ preview = { enabled = false } })
assert(not config.values.preview.enabled)
config.setup({ preview = { enabled = true } })

-- The preview callback receives Telescope's wrapped active rows. It must use
-- the cached session snapshot rather than formatting the wrapper as a session.
local preview_definition
package.loaded["telescope.previewers"] = {
    new_buffer_previewer = function(options)
        preview_definition = options
        return options
    end,
}
local previewer = assert(preview.new({ show_agents = true }))
assert(previewer == preview_definition)
local preview_buffer = vim.api.nvim_create_buf(false, true)
local preview_self = { state = { bufnr = preview_buffer } }
local active_snapshot = {
    sessions = { session },
    agents_by_id = {
        [session.id] = { { id = "pi", name = "pi", status = "working", info = "reviewing UI" } },
    },
    focused_by_id = {},
    marks_by_id = {},
    current_id = session.id,
}
local finders = require("telescope._extensions.sess.finders")
local active_finder = finders.generate_active_finder_from_snapshot(active_snapshot, {}, "all")
local active_entry = active_finder.entry_maker(active_finder.results[1])
assert(active_entry.value.session_id == session.id)
local original_preview = api.session.preview
api.session.preview = function()
    return true, nil, { snapshot_available = true }
end
preview_definition.define_preview(preview_self, active_entry, {
    picker = { _sess_active_snapshot = active_snapshot, _sess_active_loading = false },
})
local active_text = table.concat(vim.api.nvim_buf_get_lines(preview_buffer, 0, -1, false), "\n")
assert(active_text:find("Session:%s+frontend"))
assert(active_text:find("pi%s+working%s+reviewing UI"))
assert(not active_text:find("No session selected", 1, true))

-- Deleted finder entries are already complete records. Previewing them must
-- not ask the live-session query to resolve their id.
local _, _, deleted_item = api.session.create(fixture.directory("deleted-preview"), {
    name = "deleted-preview",
})
assert(api.session.delete(deleted_item))
local deleted_finder = finders.generate_deleted_finder()
local deleted_raw = deleted_finder.results[1]
local deleted_entry = deleted_finder.entry_maker(deleted_raw)
local preview_calls = 0
api.session.preview = function()
    preview_calls = preview_calls + 1
    return false, "session not found"
end
preview_definition.define_preview(preview_self, deleted_entry, { picker = {} })
local deleted_text = table.concat(vim.api.nvim_buf_get_lines(preview_buffer, 0, -1, false), "\n")
assert(deleted_text:find("State:%s+deleted"))
assert(deleted_text:find("Restore key:"))
assert(not deleted_text:find("session not found", 1, true))
assert(preview_calls == 0)
api.session.preview = original_preview
vim.api.nvim_buf_delete(preview_buffer, { force = true })

-- Formatting is pure: rendering a preview does not enter or mutate a session.
local lifecycle_calls = 0
local original_load = require("sess.api").session.load
require("sess.api").session.load = function(...)
    lifecycle_calls = lifecycle_calls + 1
    return original_load(...)
end
preview.format(session)
assert(lifecycle_calls == 0)
require("sess.api").session.load = original_load
