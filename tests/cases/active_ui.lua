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
assert(config.values.active_expand == "none")
local invalid_config = pcall(config.setup, { active_expand = "invalid" })
assert(not invalid_config)
assert(not pcall(config.setup, { poll_interval = 0 }))
config.setup({ active_expand = "none", poll_interval = 250 })
assert(config.values.active_expand == "none")
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
assert(all_finder.results[2].kind == "placeholder")

local current_finder = finders.generate_active_finder({}, "current")
local current_headers = session_headers(current_finder.results)
assert(not current_headers[first.id].expanded)
assert(current_headers[second.id].expanded)
assert(current_headers[first.id].display:find("○", 1, true))
assert(current_headers[second.id].display:find("●", 1, true))

local none_finder = finders.generate_active_finder({}, "none")
local none_headers = session_headers(none_finder.results)
assert(not none_headers[first.id].expanded)
assert(not none_headers[second.id].expanded)

local manual_expansion = { [first.id] = false }
local preserved_finder = finders.generate_active_finder(manual_expansion, "all")
assert(not session_headers(preserved_finder.results)[first.id].expanded)

local active_rows = finders.build_active_entries(
    {
        {
            id = "fake",
            metadata = { name = "project", cwd = "/tmp/project" },
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
assert(active_rows[1].display:find("agents 2 working 1 idle", 1, true))
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
assert(session_entry.display:find("○", 1, true))
assert(session_entry.display:find("@s", 1, true))
assert(session_entry.display:find("[last]", 1, true))

local pickers = require("telescope._extensions.sess.pickers")
pickers.sess()
pickers.restore()
pickers.active()
assert(active_poll_interval == 250)
for _, options in ipairs(picker_options) do
    assert(options.sorting_strategy == "ascending")
    assert(options.layout_config.prompt_position == "top")
end

local restore_picker_options = picker_options[2]
assert(restore_picker_options.get_status_text() == "<CR> restore   ? actions")
local active_picker_options = picker_options[3]
assert(active_picker_options.prompt_title == "ACTIVE SESSIONS · 2 sessions · 0 agents")
assert(getmetatable(active_picker_options.sorter) == sorter_methods)
assert(type(active_picker_options.sorter._init) == "function")
assert(type(active_picker_options.sorter._destroy) == "function")
local status_text = active_picker_options.get_status_text()
assert(status_text == "<C-b> mark   <CR> switch/focus   <S-Tab> all   <Tab> expand   ? actions")
for _, row in ipairs(active_picker_options.finder.results) do
    assert(row.kind ~= "agent", "active picker should hydrate agents asynchronously")
    if row.kind == "session" then
        assert(row.display:find("agents loading", 1, true))
    end
end

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
    created_pickers[3].layout.prompt.border.title
        == "ACTIVE SESSIONS · 2 sessions · 3 agents"
)

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
assert(stale_rows[1].display:find("agents stale", 1, true))

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
assert(config.values.active_mappings.i["<C-b>"] == actions.mark_session)
assert(config.values.active_mappings.n["<C-b>"] == actions.mark_session)
local original_snapshot = require("sess.api").active.snapshot
local snapshot_calls = 0
require("sess.api").active.snapshot = function(...)
    snapshot_calls = snapshot_calls + 1
    return original_snapshot(...)
end
actions.toggle_active(1)
assert(refresh_count == 1)
assert(snapshot_calls == 0, "expansion should reuse the active snapshot")
require("sess.api").active.snapshot = original_snapshot

selected = { value = { kind = "placeholder", session_id = first.id } }
actions.active_enter(1)
assert(not closed)
