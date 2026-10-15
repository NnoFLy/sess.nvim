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
assert(rendered:find("Pin:%s+pinned"))
assert(rendered:find("Editor"))
assert(rendered:find("Action"))

local independent = preview.format(session, {
    show_editor_summary = false,
    show_action_hint = false,
    show_snapshot_summary = false,
    show_agents = false,
})
local independent_text = table.concat(independent, "\n")
assert(not independent_text:find("Editor", 1, true))
assert(not independent_text:find("Action", 1, true))
assert(not independent_text:find("Stored state", 1, true))
assert(not independent_text:find("Agents", 1, true))

local bounded = preview.format(session, {
    agents = {
        { name = "one", status = "idle" },
        { name = "two", status = "working" },
        { name = "three", status = "blocked" },
    },
    max_agents = 2,
})
local bounded_text = table.concat(bounded, "\n")
assert(bounded_text:find("one%s+idle"))
assert(bounded_text:find("two%s+working"))
assert(bounded_text:find("and 1 more agents", 1, true))
assert(not bounded_text:find("three%s+blocked"))

local malformed_agents = preview.format(session, {
    agents = {
        { name = "valid", status = "idle" },
        "not an agent",
        { status = "working" },
    },
})
local malformed_agents_text = table.concat(malformed_agents, "\n")
assert(malformed_agents_text:find("valid%s+idle"))
assert(malformed_agents_text:find("unknown%s+working"))
assert(malformed_agents_text:find("Warning: ignored malformed agent data", 1, true))

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

-- Missing and unreadable snapshots remain visible as diagnostics instead of
-- becoming indistinguishable from a session with no stored state.
local storage = require("sess.storage")
local _, _, missing_item = api.session.create(fixture.directory("missing-preview"), {
    name = "missing-preview",
})
local missing_path = assert(storage.get_session_path(missing_item.id))
assert(vim.fn.delete(missing_path) == 0)
local missing_ok, missing_err, missing_result = api.session.preview(missing_item.id)
assert(missing_ok and not missing_err)
assert(missing_result.snapshot_status == "unavailable")
assert(missing_result.snapshot_available == false)
assert(missing_result.snapshot_error:find("regular file", 1, true))
local missing_rendered = table.concat(preview.format(missing_item, missing_result), "\n")
assert(missing_rendered:find("Snapshot:%s+unavailable"))
assert(missing_rendered:find("regular file", 1, true))

local original_inspect_snapshot = storage.inspect_snapshot
storage.inspect_snapshot = function()
    return "unavailable", "failed to read session file: permission denied"
end
local unreadable_ok, unreadable_err, unreadable_result = api.session.preview(malformed_item.id)
storage.inspect_snapshot = original_inspect_snapshot
assert(unreadable_ok and not unreadable_err)
assert(unreadable_result.snapshot_status == "unavailable")
assert(unreadable_result.snapshot_available == false)
assert(unreadable_result.snapshot_error:find("permission denied", 1, true))
local unreadable_rendered = table.concat(preview.format(malformed_item, unreadable_result), "\n")
assert(unreadable_rendered:find("Snapshot:%s+unavailable"))
assert(unreadable_rendered:find("permission denied", 1, true))

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
assert(not pcall(config.setup, { preview = { show_editor_summary = "yes" } }))
assert(not pcall(config.setup, { preview = { show_action_hint = "yes" } }))
assert(not pcall(config.setup, { preview = { max_agents = 0 } }))
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
local original_active_inspect = storage.inspect_snapshot
local active_preview_calls = 0
storage.inspect_snapshot = function()
    active_preview_calls = active_preview_calls + 1
    return "available"
end
local cached_picker = { _sess_active_snapshot = active_snapshot, _sess_active_loading = false }
preview_definition.define_preview(preview_self, active_entry, { picker = cached_picker })
preview_definition.define_preview(preview_self, active_entry, { picker = cached_picker })
assert(active_preview_calls == 1)
local active_text = table.concat(vim.api.nvim_buf_get_lines(preview_buffer, 0, -1, false), "\n")
assert(active_text:find("Session:%s+frontend"))
assert(active_text:find("pi%s+working%s+reviewing UI"))
assert(not active_text:find("No session selected", 1, true))

-- Explicit invalidation makes the next preview probe observe fresh data.
preview.invalidate(cached_picker)
preview_definition.define_preview(preview_self, active_entry, { picker = cached_picker })
assert(active_preview_calls == 2)
storage.inspect_snapshot = original_active_inspect

-- A failed editor-view probe stays in the preview as a diagnostic.
local state = require("sess.state")
local original_get_view = state.get_view
state.get_view = function()
    error("editor view unavailable")
end
preview.invalidate(cached_picker)
preview_definition.define_preview(preview_self, active_entry, { picker = cached_picker })
state.get_view = original_get_view
local editor_failure_text = table.concat(
    vim.api.nvim_buf_get_lines(preview_buffer, 0, -1, false),
    "\n"
)
assert(editor_failure_text:find("Editor"))
assert(editor_failure_text:find("unavailable", 1, true))
assert(editor_failure_text:find("editor view unavailable", 1, true))

-- A failed active-data probe is represented by an empty agent list plus a
-- stale marker. The preview must not render that empty list as authoritative.
local stale_snapshot = {
    sessions = { session },
    agents_by_id = { [session.id] = {} },
    focused_by_id = {},
    marks_by_id = {},
    stale_by_id = { [session.id] = true },
    current_id = session.id,
}
preview_definition.define_preview(preview_self, active_entry, {
    picker = { _sess_active_snapshot = stale_snapshot, _sess_active_loading = false },
})
local stale_text = table.concat(vim.api.nvim_buf_get_lines(preview_buffer, 0, -1, false), "\n")
assert(stale_text:find("unavailable (stale)", 1, true))
assert(not stale_text:find("  none", 1, true))

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

-- Telescope closes preview windows without retaining their scratch buffers.
local cleanup_buffer = vim.api.nvim_create_buf(false, true)
local cleanup_window = vim.api.nvim_open_win(cleanup_buffer, false, {
    relative = "editor",
    row = 0,
    col = 0,
    width = 20,
    height = 3,
    style = "minimal",
})
preview_definition.define_preview(
    { state = { bufnr = cleanup_buffer } },
    active_entry,
    { picker = cached_picker }
)
assert(vim.bo[cleanup_buffer].bufhidden == "wipe")
vim.api.nvim_win_close(cleanup_window, true)
assert(not vim.api.nvim_buf_is_valid(cleanup_buffer))
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
