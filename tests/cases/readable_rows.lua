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
assert(rows[1].display:find("agents 1 working", 1, true))
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
