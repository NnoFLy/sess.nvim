fixture.setup()

package.loaded["telescope.finders"] = {
    new_table = function(options)
        return options
    end,
}
package.loaded["telescope._extensions.sess.config"] = {
    values = {
        display = {
            show_metadata = true,
            show_agent_summary = true,
            path_style = "full",
            highlights = { agent = "SessTestAgent" },
        },
    },
}

local finders = require("telescope._extensions.sess.finders")
local session = {
    id = "wide",
    metadata = {
        name = "界面",
        cwd = "/home/example/projects/a-very-long-session-directory",
        pinned = true,
    },
}

-- Pinned rows use a fixed icon column, while the previous-session marker
-- replaces the state icon without shifting the remaining columns.
for _, active in ipairs({ false, true }) do
    local state_icon = active and "○" or "·"
    for _, width in ipairs({ 28, 80, 200 }) do
        local options = {
            active = active,
            mark = "@a",
            display = { available_width = width },
        }
        local normal = finders.format_session_display(session, options)
        options.previous_id = session.id
        local previous = finders.format_session_display(session, options)
        assert(previous:find("  ★ ◆ ", 1, true) == 1)
        assert(not previous:find(state_icon, 1, true))
        assert(not previous:find("[pinned]", 1, true))
        assert(not previous:find("[new session]", 1, true))
        for _, value in ipairs({ "@a", "界面" }) do
            local previous_start = assert(previous:find(value, 1, true))
            local normal_start = assert(normal:find(value, 1, true))
            assert(
                vim.fn.strdisplaywidth(previous:sub(1, previous_start - 1))
                    == vim.fn.strdisplaywidth(normal:sub(1, normal_start - 1))
            )
        end
        assert(vim.fn.strdisplaywidth(previous) == vim.fn.strdisplaywidth(normal))

        options.display.show_metadata = false
        local hidden = finders.format_session_display(session, options)
        assert(hidden:find(state_icon, 1, true))
        assert(not hidden:find("★", 1, true))
        assert(not hidden:find("◆", 1, true))
    end
end

local new_session = finders.format_session_display({
    id = nil,
    metadata = { name = "new", cwd = "/tmp/new", pinned = false },
}, { display = { available_width = 80 } })
assert(new_session:find("    + ", 1, true) == 1)
assert(not new_session:find("[new session]", 1, true))

local narrow = finders.format_session_display(session, {
    current_id = session.id,
    mark = "@a",
    mark_width = 3,
    name_width = vim.fn.strdisplaywidth(session.metadata.name),
    path_width = 14,
    display = { available_width = 14 },
})
assert(narrow:find("●", 1, true))
assert(narrow:find("界面", 1, true))
assert(narrow:find("…", 1, true))
assert(not narrow:find(session.metadata.cwd, 1, true))

local rows = finders.build_active_entries(
    { session },
    {
        wide = {
            { id = "agent", name = "代理", status = "working", info = "reviewing" },
        },
    },
    { wide = true },
    session.id,
    { wide = "agent" },
    { wide = "@a" },
    nil,
    { available_width = 200 }
)
assert(rows[1].display:find("@a", 1, true))
local agent_status_start = assert(rows[1].display:find("  agents 1 working", 1, true))
assert(vim.fn.strdisplaywidth(rows[1].display) == 200)
assert(
    vim.fn.strdisplaywidth(rows[1].display:sub(agent_status_start))
        == vim.fn.strdisplaywidth("  agents 1 working")
)
assert(rows[2].display:find("  └─", 1, true))
assert(rows[2].display:find("代理", 1, true))
assert(rows[2].display:find("reviewing", 1, true))
assert(rows[2].display_parts[2].highlight == "SessTestAgent")
assert(rows[1].ordinal:find(session.metadata.cwd, 1, true))

local api = require("sess.api")
local marked_path = fixture.directory("marked")
local marked_ok, marked_err, marked_session = api.session.create(marked_path, { name = "marked" })
assert(marked_ok, marked_err)
assert(api.session.set_mark(marked_session, "m"))
local directory_finder = finders.generate_directory_finder(fixture.root .. "/")
local marked_entry
for _, entry in ipairs(directory_finder.results) do
    if entry.id == marked_session.id then
        marked_entry = entry
        break
    end
end
assert(marked_entry)
assert(marked_entry.ordinal:find("@m", 1, true))
