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
assert(not pcall(config.setup, { search = { fields = { "unknown" } } }))
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
assert(sorter.scoring_function("frontend", exact) > sorter.scoring_function("frontend", path))

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

-- The default fields include info even when it is absent from agent/name/status.
assert(vim.tbl_contains(config.values.search.fields, "info"))
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
    { one = { { id = "pi", name = "pi", status = "working", info = "reviewing" } } },
    {},
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

local api = require("sess.api")
local original_get_items = api.items.get_items
local original_active_snapshot = api.active.snapshot
api.items.get_items = function()
    return { session }, nil, {}
end
api.active.snapshot = function()
    return {
        agents_by_id = {
            one = { { id = "pi", name = "pi", status = "working", info = "reviewing" } },
        },
        diagnostics = {},
    }
end
local regular_finder = finders.generate_new_finder()
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
api.items.get_items = original_get_items
api.active.snapshot = original_active_snapshot
