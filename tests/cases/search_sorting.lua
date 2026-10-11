fixture.setup()

package.loaded["telescope.actions"] = {
    close = function() end,
}
package.loaded["telescope.actions.state"] = {}
package.loaded["telescope.config"] = {
    values = {
        generic_sorter = function()
            return {
                scoring_function = function(_, entry)
                    return entry.ordinal:find("path", 1, true) and 2 or 1
                end,
            }
        end,
    },
}
package.loaded["telescope.finders"] = {
    new_table = function(options)
        return options
    end,
}

local config = require("telescope._extensions.sess.config")
config.setup({ search = { filters = true, sort = "default" } })
assert(not pcall(config.setup, { search = { sort = "unknown" } }))
assert(not pcall(config.setup, { search = { cycle_sort = { x = "<C-s>" } } }))
assert(not pcall(config.setup, { search = { cycle_sort = "" } }))
assert(not pcall(config.setup, { search = { cycle_sort = { i = "" } } }))
assert(not pcall(config.setup, { search = { cycle_sort = {} } }))
assert(not pcall(config.setup, { search = { show_count = "yes" } }))
assert(not pcall(config.setup, { search = { fields = { "unknown" } } }))
assert(config.values.search.show_count == true)
assert(config.values.search.show_sort == true)
local search = require("telescope._extensions.sess.search")

-- Telescope's sorter lifecycle methods live on its metatable; the wrapper
-- used by picker_options must preserve them for active pickers as well.
local sorter_methods = { __index = { _init = function() end, _destroy = function() end } }
local wrapped = search.new_sorter(setmetatable({}, sorter_methods), {})
assert(getmetatable(wrapped) == sorter_methods)
assert(type(wrapped._init) == "function" and type(wrapped._destroy) == "function")

local session = {
    id = "one",
    metadata = {
        name = "frontend",
        cwd = "/tmp/projects/界面 with spaces",
        pinned = true,
        last_used_at = 10,
    },
}
local fields = search.fields_for_session(session, {
    mark = "@a",
    current = false,
    active = true,
    previous = true,
    agents = { { id = "pi", name = "pi", status = "working", info = "reviewing" } },
})
local ordinal = search.ordinal(fields)
assert(ordinal:find("frontend", 1, true))
assert(ordinal:find("界面 with spaces", 1, true))
assert(ordinal:find("@a", 1, true))
assert(ordinal:find("pi", 1, true))
assert(ordinal:find("working", 1, true))
assert(ordinal:find("reviewing", 1, true))

local path_filter = search.parse_filter("path:界面 with spaces", config.values.search)
assert(path_filter.field == "cwd")
assert(path_filter.query == "界面 with spaces")
assert(search.parse_filter("path:", config.values.search) == nil)
assert(search.parse_filter("not:a", config.values.search) == nil)
assert(search.parse_filter("@a", config.values.search).field == "mark")
assert(search.parse_filter("@abc", config.values.search) == nil)
assert(search.parse_filter("status:working", config.values.search).label == "status")
local mark_feedback, mark_filter = search.feedback("@a", config.values.search, 2)
assert(mark_filter.field == "mark")
assert(mark_feedback == "mark:@a  2 matches")
assert(search.next_sort("default") == "recent")
assert(search.next_sort("name") == "default")
local filter_feedback, parsed_feedback = search.feedback("path:frontend", {
    filters = true,
    show_count = true,
    show_sort = true,
    sort = "name",
}, 3)
assert(parsed_feedback.field == "cwd")
assert(filter_feedback == "path:frontend  3 matches  sort:name")
local malformed_feedback, malformed_filter = search.feedback("not:a", {
    filters = true,
    show_count = false,
    show_sort = true,
    sort = "default",
}, nil)
assert(malformed_filter == nil)
assert(malformed_feedback == nil)

local function entry(name, cwd, mark)
    local value = {
        id = name,
        metadata = { name = name, cwd = cwd, last_used_at = 1 },
    }
    return {
        value = value,
        ordinal = name .. " " .. cwd .. " " .. (mark or ""),
        search_fields = search.fields_for_session(value, { mark = mark }),
    }
end
local sorter = search.new_sorter({
    scoring_function = function()
        return 1
    end,
}, config.values.search)
local exact = entry("frontend", "/tmp/other", "")
local path = entry("other", "/tmp/frontend", "")
-- Lower scores sort first, so name matches must beat path-only matches.
local path_score = sorter.scoring_function("frontend", path)
assert(sorter.scoring_function("frontend", exact) < path_score)
local name_substring = entry("my-frontend-app", "/tmp/other", "")
assert(sorter.scoring_function("frontend", name_substring) < path_score)
-- Telescope passes the sorter, prompt, ordinal, and entry to scoring_function.
-- The extension must use the entry argument rather than the ordinal string.
assert(sorter.scoring_function(sorter, "frontend", exact.ordinal, exact) > 0)

local telescope_style_calls = 0
local telescope_style_sorter = search.new_sorter({
    scoring_function = function(_, prompt, line, scored_entry)
        telescope_style_calls = telescope_style_calls + 1
        assert(line == scored_entry.ordinal)
        return line:find(prompt, 1, true) and 1 or -1
    end,
}, config.values.search)
assert(telescope_style_sorter.scoring_function(
    telescope_style_sorter,
    "frontend",
    exact.ordinal,
    exact
) >= 0)
assert(telescope_style_calls == 1)

-- Fuzzy-only queries must reach the base sorter with the complete ordinal.
local fuzzy_calls = 0
local fuzzy_sorter = search.new_sorter({
    scoring_function = function(prompt, scored_entry)
        fuzzy_calls = fuzzy_calls + 1
        assert(scored_entry.ordinal == exact.ordinal)
        assert(scored_entry == exact)
        return #vim.fn.matchfuzzy({ scored_entry.ordinal }, prompt) > 0 and 1 or -1
    end,
}, config.values.search)
assert(not exact.ordinal:find("frnt", 1, true))
assert(fuzzy_sorter.scoring_function("frnt", exact) >= 0)
assert(fuzzy_calls == 1)
assert(fuzzy_sorter.scoring_function("zzzz", exact) < 0)
assert(fuzzy_calls == 1)
local rejecting_sorter = search.new_sorter({
    scoring_function = function()
        return -1
    end,
}, config.values.search)
assert(rejecting_sorter.scoring_function("frnt", exact) < 0)

-- The documented default includes every session-state label as well as agent
-- details, even when a particular row has no value for one of them.
for _, field in ipairs({ "pinned", "last", "current", "active", "info" }) do
    assert(vim.tbl_contains(config.values.search.fields, field), "missing default field " .. field)
end
assert(sorter.scoring_function("reviewing", {
    ordinal = "reviewing",
    search_fields = { info = "reviewing" },
}) >= 0)
assert(sorter.scoring_function("path:界面 with spaces", {
    ordinal = ordinal,
    search_fields = fields,
}) >= 0)
assert(sorter.scoring_function("status:working", {
    ordinal = ordinal,
    search_fields = fields,
}) >= 0)
assert(sorter.scoring_function("pinned", {
    ordinal = ordinal,
    search_fields = fields,
}) >= 0)
-- State fields must work in the default scope even without duplicates in
-- status. The base sorter still receives the untouched complete ordinal.
for _, label in ipairs({ "pinned", "last", "current", "active" }) do
    local state_ordinal = label .. " complete enriched ordinal"
    local state_sorter = search.new_sorter({
        scoring_function = function(_, scored_entry)
            assert(scored_entry.ordinal == state_ordinal)
            return 1
        end,
    }, config.values.search)
    assert(state_sorter.scoring_function(label, {
        ordinal = state_ordinal,
        search_fields = { [label] = label },
    }) >= 0)
end

local saw_enriched_ordinal = false
local name_only_sorter = search.new_sorter({
    scoring_function = function(prompt, scored_entry)
        saw_enriched_ordinal = scored_entry.ordinal:find("agent-only", 1, true) ~= nil
        return scored_entry.ordinal:find(prompt, 1, true) and 1 or -1
    end,
}, { fields = { "name" } })
local name_only_entry = entry("frontend", "/tmp/agent-only", "")
local public_ordinal = name_only_entry.ordinal
assert(name_only_sorter.scoring_function("agent-only", name_only_entry) < 0)
assert(name_only_entry.ordinal == public_ordinal)
assert(name_only_sorter.scoring_function("frontend", name_only_entry) > 0)
assert(saw_enriched_ordinal)

local scoped_fuzzy_calls = 0
local scoped_fuzzy_sorter = search.new_sorter({
    scoring_function = function(_, scored_entry)
        scoped_fuzzy_calls = scoped_fuzzy_calls + 1
        assert(scored_entry.ordinal == public_ordinal)
        return 1
    end,
}, { fields = { "name" } })
assert(scoped_fuzzy_sorter.scoring_function("agnt", name_only_entry) < 0)
assert(scoped_fuzzy_calls == 0)
assert(scoped_fuzzy_sorter.scoring_function("frnt", name_only_entry) >= 0)
assert(scoped_fuzzy_calls == 1)
local field_scoped_sorter = search.new_sorter(nil, { fields = { "name", "cwd" } })
assert(field_scoped_sorter.scoring_function("frntpth", entry("frontend", "/tmp/path", "")) < 0)
assert(field_scoped_sorter.scoring_function("界空", entry("界面 空间", "/tmp/other", "")) >= 0)

assert(search.parse_filter("status:working", { filters = false }) == nil)
local no_filter_sorter = search.new_sorter(nil, { filters = false })
assert(no_filter_sorter.scoring_function("status:working", {
    ordinal = ordinal,
    search_fields = fields,
}) < 0)
assert(no_filter_sorter.scoring_function("working", {
    ordinal = ordinal,
    search_fields = fields,
}) >= 0)

local function assert_order(results, ...)
    local expected = { ... }
    for index, name in ipairs(expected) do
        assert(results[index].metadata.name == name)
    end
end

local ordering = {
    { metadata = { name = "beta", pinned = true, last_used_at = 10 }, search_fields = { _activity = 5 } },
    { metadata = { name = "alpha", pinned = false, last_used_at = 30 }, search_fields = { _activity = 4 } },
    { metadata = { name = "charlie", pinned = false, last_used_at = 20 }, search_fields = { _activity = 2 } },
}
assert_order(search.sort_results(ordering, "default"), "beta", "alpha", "charlie")
assert_order(search.sort_results(ordering, "recent"), "alpha", "charlie", "beta")
assert_order(search.sort_results(ordering, "pinned"), "beta", "alpha", "charlie")
assert_order(search.sort_results(ordering, "activity"), "charlie", "alpha", "beta")
assert_order(search.sort_results(ordering, "name"), "alpha", "beta", "charlie")

local finders = require("telescope._extensions.sess.finders")
local rows = finders.build_active_entries(
    { session },
    {
        one = {
            { id = "pi", name = "pi", status = "working", info = "reviewing" },
            { id = "codex", name = "codex", status = "idle" },
        },
    },
    { one = true },
    nil,
    {},
    { one = "@a" },
    nil
)
assert(rows[1].kind == "session")
assert(rows[1].ordinal:find("pi", 1, true))
assert(rows[1].ordinal:find("working", 1, true))
local active_parent_sorter = search.new_sorter({
    scoring_function = function(prompt, scored_entry)
        return scored_entry.ordinal:find("pi", 1, true) and 1 or -1
    end,
}, config.values.search)
assert(active_parent_sorter.scoring_function("agent:pi", {
    ordinal = rows[1].ordinal,
    search_fields = rows[1].search_fields,
}) >= 0)

-- Active tree rows use the parent session's score, so Telescope cannot move
-- an agent away from its associated session header.
local hierarchy_sorter = search.new_active_sorter({
    scoring_function = function(_, _, ordinal)
        return #ordinal
    end,
}, config.values.search)
local function active_entry(row)
    return {
        ordinal = row.ordinal,
        search_fields = row.search_fields,
        active_group_fields = row.active_group_fields,
        active_group_ordinal = row.active_group_ordinal,
    }
end

local parent_entry = active_entry(rows[1])
local agent_entry = active_entry(rows[2])
assert(
    hierarchy_sorter.scoring_function("pi", parent_entry)
        == hierarchy_sorter.scoring_function("pi", agent_entry)
)
local unmatched_agent_entry = active_entry(rows[3])
assert(hierarchy_sorter.scoring_function("reviewing", unmatched_agent_entry) < 0)

local api = require("sess.api")
local original_get_items = api.items.get_items
local original_snapshot = api.active.snapshot
local original_snapshot_async = api.active.snapshot_async
api.active.snapshot = function()
    error("regular finder must not probe agents synchronously")
end
api.items.get_items = function()
    return { session }, nil, {}
end
api.active.snapshot_async = function(callback)
    callback({
        agents_by_id = {
            one = { { id = "pi", name = "pi", status = "working", info = "reviewing" } },
        },
        diagnostics = {},
    })
    return function() end
end
local unhydrated_finder = finders.generate_new_finder()
assert(unhydrated_finder)
local hydrated_finder
local cancel = finders.generate_new_finder_async({}, function(finder)
    hydrated_finder = finder
end)
assert(cancel)
local regular_finder = hydrated_finder
local regular_entry = regular_finder.entry_maker(regular_finder.results[1])
assert(regular_entry.search_fields.agent:find("pi", 1, true))
assert(regular_entry.search_fields.status:find("working", 1, true))
assert(regular_entry.ordinal:find("pi", 1, true))
assert(regular_entry.ordinal:find("working", 1, true))
assert(sorter.scoring_function("agent:pi", regular_entry) >= 0)
assert(sorter.scoring_function("status:working", regular_entry) >= 0)
assert(sorter.scoring_function("reviewing", regular_entry) >= 0)
assert(sorter.scoring_function("reviewing", {
    ordinal = rows[1].ordinal,
    search_fields = rows[1].search_fields,
}) >= 0)

api.items.get_items = function()
    return {
        { name = "new-project", path = "/tmp/new-project", pinned = false },
    }, nil, {}
end
local directory_finder = finders.generate_new_finder()
local directory_entry = directory_finder.entry_maker(directory_finder.results[1])
assert(directory_entry.value.directory)
assert(directory_entry.value.path == "/tmp/new-project")
local directory_root = fixture.directory("finder-directory")
fixture.directory("finder-directory/zeta")
fixture.directory("finder-directory/alpha")
local hydrated_directory_finder
local original_sort_results = search.sort_results
local directory_sort_mode
search.sort_results = function(results, mode)
    directory_sort_mode = mode
    return original_sort_results(results, mode)
end
local initial_directory_finder, directory_cancel = finders.generate_directory_finder(
    directory_root .. "/",
    nil,
    function(finder)
        hydrated_directory_finder = finder
    end,
    nil,
    { sort = "name" }
)
assert(directory_sort_mode == "name")
search.sort_results = original_sort_results
assert(
    initial_directory_finder.results[2].path:match("/alpha$")
        or initial_directory_finder.results[2].path:match("/alpha/$")
)
assert(hydrated_directory_finder)
assert(directory_cancel)
assert(#hydrated_directory_finder.results == #initial_directory_finder.results)

-- Directory rows must remain visible when the prompt is a path alias. The
-- regular session sorter still filters the directory finder, so this guards
-- the contract between path mode and searchable ordinals.
for _, prompt in ipairs({ "./", "../", "~/", "/", fixture.root .. "/", "./finder-directory" }) do
    local finder = finders.generate_directory_finder(prompt)
    assert(#finder.results > 0, "no directory results for " .. prompt)
    local entry = finder.entry_maker(finder.results[1])
    assert(entry.value.directory)
    assert(entry.ordinal:find(prompt, 1, true), "directory ordinal lost prompt " .. prompt)
    assert(
        sorter.scoring_function(prompt, entry) >= 0,
        "directory prompt was rejected by sorter: " .. prompt
    )
end

local escaped_path_entry = {
    value = { directory = true, prompt = "./project with space/" },
    search_fields = {},
    ordinal = "./project with space/",
}
assert(sorter.scoring_function("./project\\ with", escaped_path_entry) >= 0)
assert(sorter.scoring_function("./missing", escaped_path_entry) < 0)

api.items.get_items = original_get_items
api.active.snapshot = original_snapshot
api.active.snapshot_async = original_snapshot_async
