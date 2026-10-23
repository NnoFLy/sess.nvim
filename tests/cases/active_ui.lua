fixture.setup()

local api = require("sess.api")
local _, _, first = api.session.create(fixture.directory("first"), { name = "first" })
assert(api.session.load(first))
local _, _, second = api.session.create(fixture.directory("second"), { name = "second" })
assert(api.session.load(second))
assert(api.session.set_mark(first, "s"))

local selected
local closed = false
package.loaded["telescope.actions"] = {
    close = function()
        closed = true
    end,
}
package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
        return selected
    end,
}
package.loaded["telescope.finders"] = {
    new_table = function(value)
        return value
    end,
}
local sorter_methods = {
    __index = {
        _init = function() end,
        _destroy = function() end,
    },
}
package.loaded["telescope.config"] = {
    values = {
        generic_sorter = function()
            return setmetatable({}, sorter_methods)
        end,
    },
}

local config = require("telescope._extensions.sess.config")
local status_highlights = config.values.display.highlights
assert(status_highlights.blocked == "SessStatusBlocked")
assert(status_highlights.unknown == "SessStatusUnknown")
assert(status_highlights.stale == "SessStatusStale")
assert(status_highlights.blocked ~= status_highlights.unknown)
assert(status_highlights.blocked ~= status_highlights.stale)
assert(status_highlights.unknown ~= status_highlights.stale)

vim.api.nvim_set_hl(0, "SessStatusBlocked", { fg = "#abcdef" })
assert(config.values.active_expand == "none")
assert(config.values.active.header_navigation)
assert(config.values.active.refresh_key == "<C-r>")
assert(config.values.active.next_header_key == "<C-j>")
assert(not pcall(config.setup, { active = { refresh_key = "" } }))
assert(not pcall(config.setup, { active = { next_header_key = 12 } }))
assert(not pcall(config.setup, { active = { refresh_key = "<C-j>" } }))
assert(not pcall(config.setup, {
    active = { next_header_key = "<C-x>", previous_header_key = "<C-x>" },
}))
assert(not pcall(config.setup, {
    display = { highlights = { unsupported_field = "SessUnsupported" } },
}))
local invalid_config = pcall(config.setup, { active_expand = "invalid" })
assert(not invalid_config)
assert(not pcall(config.setup, { poll_interval = 0 }))
config.setup({ active_expand = "none", poll_interval = 250 })
assert(vim.api.nvim_get_hl(0, { name = "SessStatusBlocked", link = true }).fg == 0xABCDEF)
assert(vim.api.nvim_get_hl(0, { name = "SessStatusUnknown", link = true }).link == "DiagnosticInfo")
assert(vim.api.nvim_get_hl(0, { name = "SessStatusStale", link = true }).link == "DiagnosticHint")
config.setup({
    display = {
        highlights = {
            blocked = "SessTestBlocked",
            unknown = "SessTestUnknown",
        },
    },
})
assert(config.values.display.highlights.blocked == "SessTestBlocked")
assert(config.values.display.highlights.unknown == "SessTestUnknown")
assert(config.values.display.highlights.stale == "SessStatusStale")
config.setup({ active_expand = "all" })
assert(config.values.sorting_strategy == "ascending")
assert(config.values.layout_config.prompt_position == "top")

local picker_options = {}
local created_pickers = {}
local active_poll_interval
local active_generate
package.loaded["telescope.pickers"] = {
    new = function(options)
        picker_options[#picker_options + 1] = options
        local picker = {
            layout = { prompt = { border = {} } },
            find = function() end,
        }
        function picker.layout.prompt.border:change_title(title)
            self.title = title
        end
        created_pickers[#created_pickers + 1] = picker
        return picker
    end,
}
package.loaded["sess.ui.active_refresh"] = {
    start = function(_, generate, _, poll_interval)
        active_poll_interval = poll_interval
        active_generate = generate
    end,
}

local finders = require("telescope._extensions.sess.finders")
local function session_headers(rows)
    local result = {}
    for _, row in ipairs(rows) do
        if row.kind == "session" then
            result[row.session_id] = row
        end
    end
    return result
end

local all_finder = finders.generate_active_finder({}, "all")
local all_headers = session_headers(all_finder.results)
assert(all_headers[first.id].expanded)
assert(all_headers[second.id].expanded)
assert(all_headers[first.id].display:find("@s", 1, true))
assert(all_headers[first.id].display:find("▾ ◆ ", 1, true) == 1)
assert(not all_headers[first.id].display:find("★", 1, true))
assert(not all_headers[first.id].display:find("expanded", 1, true))
assert(
    finders.format_session_metadata({ last_used_at = 7200, created_at = 0 }, 10800)
        == "last used 1h ago · age unknown"
)
assert(#all_finder.results == 2)
assert(all_finder.results[2].kind == "session")

local current_finder = finders.generate_active_finder({}, "current")
local current_headers = session_headers(current_finder.results)
assert(not current_headers[first.id].expanded)
assert(current_headers[second.id].expanded)
assert(current_headers[first.id].display:find("◆", 1, true))
assert(current_headers[second.id].display:find("●", 1, true))

local none_finder = finders.generate_active_finder({}, "none")
local none_headers = session_headers(none_finder.results)
assert(not none_headers[first.id].expanded)
assert(not none_headers[second.id].expanded)
assert(none_headers[first.id].display:find("▸", 1, true))
assert(not none_headers[first.id].display:find("collapsed", 1, true))

local manual_expansion = { [first.id] = false }
local preserved_finder = finders.generate_active_finder(manual_expansion, "all")
assert(not session_headers(preserved_finder.results)[first.id].expanded)

local active_rows = finders.build_active_entries(
    {
        {
            id = "fake",
            metadata = { name = "project", cwd = "/tmp/project", pinned = true },
        },
    },
    {
        fake = {
            { id = "pi", name = "pi", status = "working", info = "implementing auth" },
            { id = "codex", name = "codex", status = "working" },
            { id = "claude", name = "claude", status = "idle" },
        },
    },
    { fake = true },
    "fake",
    { fake = "pi" }
)
assert(active_rows[1].display:find("/tmp/project", 1, true))
assert(active_rows[1].display:find("agents: 2 working · 1 idle", 1, true))
assert(not active_rows[1].display:find("★", 1, true))
assert(active_rows[2].display:find("─", 1, true))
assert(active_rows[2].display:find("working", 1, true))
assert(active_rows[2].display:find("implementing auth", 1, true))
assert(not active_rows[2].display:find("/tmp/project", 1, true))
assert(active_rows[2].display:find(">", 1, true))
assert(active_rows[2].ordinal:find("/tmp/project", 1, true))

local session_finder = finders.generate_new_finder()
local session_entry
for _, raw in ipairs(session_finder.results) do
    local entry = session_finder.entry_maker(raw)
    if entry and entry.value.id == first.id then
        session_entry = entry
        break
    end
end
assert(session_entry)
assert(session_entry.display:find("@s", 1, true))
assert(session_entry.display:find("last used", 1, true))
assert(session_entry.display:find("age", 1, true))
assert(not session_entry.display:find("agents", 1, true))
local previous_icon = session_entry.display:find("◆", 1, true)
local session_name = session_entry.display:find("@s", 1, true)
assert(previous_icon and previous_icon < session_name)
assert(session_entry.display:find("    ◆ ", 1, true) == 1)
assert(not session_entry.display:find("○", 1, true))
assert(not session_entry.display:find("[last]", 1, true))

local pickers = require("telescope._extensions.sess.pickers")
local active_actions = require("telescope._extensions.sess.actions")
local api = require("sess.api")
local original_active_state = api.state.active
local active_state_reads = 0
api.state.active = function(...)
    active_state_reads = active_state_reads + 1
    return original_active_state(...)
end
pickers.sess()
pickers.restore()
active_state_reads = 0
pickers.active()
api.state.active = original_active_state
assert(active_state_reads == 1, "active picker should read active state once")
assert(active_poll_interval == 250)
for _, options in ipairs(picker_options) do
    assert(options.sorting_strategy == "ascending")
    assert(options.layout_config.prompt_position == "top")
end

local restore_picker_options = picker_options[2]
assert(restore_picker_options.get_status_text() == "? - help")
local active_picker_options = picker_options[3]
assert(active_picker_options.prompt_title == "ACTIVE SESSIONS · 2 sessions · 0 agents")
assert(active_picker_options.sorter._sess_active_sorter)
assert(getmetatable(active_picker_options.sorter) == sorter_methods)
assert(type(active_picker_options.sorter._init) == "function")
assert(type(active_picker_options.sorter._destroy) == "function")
local status_text = active_picker_options.get_status_text()
assert(status_text == "? - help")
for _, row in ipairs(active_picker_options.finder.results) do
    assert(row.kind ~= "agent", "active picker should hydrate agents asynchronously")
    if row.kind == "session" then
        assert(row.display:find("agents: loading", 1, true))
    end
end

-- Refresh mapping is independent from optional header navigation, while a
-- generated refresh/header collision is rejected instead of silently dropping
-- one action.
assert(not pcall(pickers.active, { active = { refresh_key = "<C-j>" } }))
pickers.active({ active = { header_navigation = false, refresh_key = "<C-x>" } })
local independent_active_options = picker_options[4]
assert(independent_active_options.attach_mappings)
-- Inspect the generated mappings through the status/help callback, which uses
-- the same table passed to attach_mappings.
local mapped = {}
independent_active_options.attach_mappings(1, function(mode, key, action)
    mapped[mode] = mapped[mode] or {}
    mapped[mode][key] = action
end)
assert(mapped.i["<C-x>"] == active_actions.refresh_active)
assert(mapped.n["<C-x>"] == active_actions.refresh_active)
assert(mapped.i["<C-r>"] == active_actions.rename_session)
assert(mapped.i["<C-j>"] == nil)
assert(mapped.i["<C-k>"] == nil)
local independent_status = independent_active_options.get_status_text()
assert(independent_status == "? - help")

local hydrated_snapshot = {
    sessions = { { id = "one" }, { id = "two" } },
    agents_by_id = {
        one = { { id = "working", status = "working" }, { id = "blocked", status = "blocked" } },
        two = { { id = "idle", status = "idle" } },
    },
    agents_loaded_by_id = { one = true, two = true },
}
local original_generate_active_finder_async = finders.generate_active_finder_async
finders.generate_active_finder_async = function(_, _, callback)
    callback({}, {}, hydrated_snapshot)
end
active_generate({}, function() end)
finders.generate_active_finder_async = original_generate_active_finder_async
assert(
    created_pickers[4].layout.prompt.border.title
        == "ACTIVE SESSIONS · 2 sessions · 3 agents"
)

local function active_mapping_options(options)
    pickers.active(options)
    local result = { i = {}, n = {} }
    picker_options[#picker_options].attach_mappings(1, function(mode, key, action)
        result[mode][key] = action
    end)
    return result
end
assert(not pcall(pickers.active, {
    active = { next_header_key = "<C-x>", previous_header_key = "<C-x>" },
}))
local overridden_refresh = function() end
local overridden_mappings = active_mapping_options({
    active = { refresh_key = "<C-x>" },
    mappings = { i = { ["<C-x>"] = false }, n = { ["<C-x>"] = overridden_refresh } },
})
assert(overridden_mappings.i["<C-x>"] == nil, "false must disable generated refresh")
assert(overridden_mappings.n["<C-x>"] == overridden_refresh, "configured refresh key wins")
local explicit_refresh_mappings = active_mapping_options({
    active = { refresh_key = "<C-x>" },
    mappings = {
        i = { ["<C-r>"] = active_actions.refresh_active },
        n = { ["<C-r>"] = active_actions.refresh_active },
    },
})
assert(
    explicit_refresh_mappings.i["<C-r>"] == active_actions.refresh_active,
    "explicit refresh mapping must be preserved when using an alternate key"
)
assert(explicit_refresh_mappings.i["<C-x>"] == active_actions.refresh_active)
local explicit_refresh_disabled = active_mapping_options({
    active = { refresh_key = false },
    mappings = {
        i = { ["<C-r>"] = active_actions.refresh_active },
        n = { ["<C-r>"] = active_actions.refresh_active },
    },
})
assert(
    explicit_refresh_disabled.i["<C-r>"] == active_actions.refresh_active,
    "explicit refresh mapping must be preserved when refresh generation is disabled"
)
local disabled_mappings = active_mapping_options({ active = { refresh_key = false } })
assert(disabled_mappings.i["<C-r>"] == active_actions.rename_session)
assert(disabled_mappings.n["<C-r>"] == nil)
assert(disabled_mappings.i["<C-j>"] == active_actions.next_active_header)
assert(disabled_mappings.n["<C-k>"] == active_actions.previous_active_header)
local header_disabled_mappings = active_mapping_options({
    active = { header_navigation = false, refresh_key = "<C-j>" },
})
assert(header_disabled_mappings.i["<C-j>"] == active_actions.refresh_active)
assert(header_disabled_mappings.n["<C-j>"] == active_actions.refresh_active)

local inherited_action = function() end
local inherited_delete = function() end
local inherited_mappings = active_mapping_options({
    active = { header_navigation = false, refresh_key = false },
    mappings = {
        i = {
            ["<C-y>"] = inherited_action,
            ["<C-d>"] = inherited_delete,
            ["<S-Tab>"] = inherited_delete,
            ["<C-o>"] = inherited_action,
        },
        n = {},
    },
})
assert(inherited_mappings.i["<C-y>"] == inherited_action)
assert(inherited_mappings.i["<C-d>"] == inherited_delete)
assert(inherited_mappings.i["<Tab>"] == active_actions.toggle_active)
assert(inherited_mappings.i["<CR>"] == active_actions.active_enter)
assert(inherited_mappings.i["<S-Tab>"] == active_actions.toggle_all_active)
assert(inherited_mappings.i["<C-o>"] == inherited_action)

local dashboard = finders.active_dashboard_summary({
    sessions = { { id = "one" }, { id = "two" } },
    agents_by_id = {
        one = { { id = "working", status = "working" }, { id = "blocked", status = "blocked" } },
        two = { { id = "idle", status = "idle" } },
    },
    agents_loaded_by_id = { one = true, two = true },
})
assert(dashboard.session_count == 2)
assert(dashboard.agent_count == 3)
assert(dashboard.status_counts.working == 1)
assert(
    finders.active_dashboard_title({ sessions = {}, agents_by_id = {} })
        == "ACTIVE SESSIONS · 0 sessions · 0 agents"
)

local stale_rows = finders.build_active_entries(
    { { id = "stale", metadata = { name = "stale", cwd = "/tmp/stale" } } },
    { stale = {} },
    {},
    nil,
    {},
    {},
    nil,
    nil,
    { stale = true },
    { stale = true }
)
assert(stale_rows[1].display:find("agents: stale", 1, true))

local refresh_count = 0
local active_picker = {
    _sess_expanded = { [first.id] = true },
    _sess_active_expand = "all",
    _sess_active_snapshot = require("sess.api").active.initial_snapshot(),
    refresh = function()
        refresh_count = refresh_count + 1
    end,
}
package.loaded["telescope.actions.state"].get_current_picker = function()
    return active_picker
end
selected = { value = { kind = "session", session_id = first.id } }
local actions = require("telescope._extensions.sess.actions")
assert(config.values.mappings.i["<C-b>"] == actions.mark_session)
assert(config.values.mappings.n["<C-b>"] == actions.mark_session)
assert(config.values.active_mappings == nil)
local original_snapshot = require("sess.api").active.snapshot
local original_generate_active = finders.generate_active_finder_from_snapshot
local observed_sort
finders.generate_active_finder_from_snapshot = function(
    snapshot,
    expanded_by_id,
    active_expand,
    display_opts,
    search_options
)
    observed_sort = search_options and search_options.sort
    return original_generate_active(
        snapshot,
        expanded_by_id,
        active_expand,
        display_opts,
        search_options
    )
end
active_picker._sess_search_options = { sort = "name" }
active_picker._sess_sort_mode = "name"
local snapshot_calls = 0
require("sess.api").active.snapshot = function(...)
    snapshot_calls = snapshot_calls + 1
    return original_snapshot(...)
end
actions.toggle_active(1)
assert(refresh_count == 1)
assert(observed_sort == "name", "active expansion must preserve non-default sort mode")
assert(snapshot_calls == 0, "expansion should reuse the active snapshot")
active_picker._sess_help_kind = "active"
selected = { value = { kind = "agent", session_id = first.id, agent_id = "agent" } }
actions.cycle_sort(1)
assert(refresh_count == 2)
assert(
    observed_sort == "default",
    "active sort cycling must preserve the selected agent: " .. tostring(observed_sort)
)
finders.generate_active_finder_from_snapshot = original_generate_active
require("sess.api").active.snapshot = original_snapshot

selected = { value = { kind = "placeholder", session_id = first.id } }
actions.active_enter(1)
assert(not closed)
