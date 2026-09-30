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
package.loaded["telescope.config"] = {
    values = { generic_sorter = function() end },
}

local config = require("telescope._extensions.sess.config")
local invalid_config = pcall(config.setup, { active_expand = "invalid" })
assert(not invalid_config)
config.setup({ active_expand = "none" })
assert(config.values.active_expand == "none")
config.setup({ active_expand = "all" })
assert(config.values.sorting_strategy == "ascending")
assert(config.values.layout_config.prompt_position == "top")

local picker_options = {}
package.loaded["telescope.pickers"] = {
    new = function(options)
        picker_options[#picker_options + 1] = options
        return { find = function() end }
    end,
}
package.loaded["sess.ui.active_refresh"] = { start = function() end }

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
        },
    },
    { fake = true },
    "fake",
    { fake = "pi" }
)
assert(active_rows[1].display:find("/tmp/project", 1, true))
assert(active_rows[2].display:find("─", 1, true))
assert(active_rows[2].display:find("working", 1, true))
assert(active_rows[2].display:find("implementing auth", 1, true))
assert(not active_rows[2].display:find("/tmp/project", 1, true))
assert(active_rows[2].display:find(">", 1, true))
assert(active_rows[2].ordinal:find("/tmp/project", 1, true))

local pickers = require("telescope._extensions.sess.pickers")
pickers.sess()
pickers.restore()
pickers.active()
for _, options in ipairs(picker_options) do
    assert(options.sorting_strategy == "ascending")
    assert(options.layout_config.prompt_position == "top")
end

selected = { value = { kind = "placeholder", session_id = first.id } }
local actions = require("telescope._extensions.sess.actions")
assert(config.values.mappings.i["<C-b>"] == actions.mark_session)
assert(config.values.mappings.n["<C-b>"] == actions.mark_session)
assert(config.values.active_mappings.i["<C-b>"] == actions.mark_session)
assert(config.values.active_mappings.n["<C-b>"] == actions.mark_session)
actions.toggle_active(1)
actions.active_enter(1)
assert(not closed)
