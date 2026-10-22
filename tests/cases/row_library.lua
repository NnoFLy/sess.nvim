local rows = require("sess.ui.rows")

local first = { id = "one", metadata = { name = "one", cwd = "/projects/one", pinned = false } }
local second = { id = "two", metadata = { name = "two", cwd = "/projects/two", pinned = false } }

assert(rows.session_key("one") ~= rows.agent_key("one", "one"))
assert(rows.session_key("one") ~= rows.key("placeholder", "one"))
assert(rows.directory_key("/projects/one") == rows.directory_key("/projects/one"))
assert(rows.directory_key("/projects/one") ~= rows.directory_key("/projects/two"))

local expanded, expanded_meta = rows.build_active({
    sessions = { first, second },
    agents_by_id = {
        one = { { id = "agent", name = "agent", status = "working", info = "a-full-path-value" } },
        two = "malformed",
    },
    expanded = { one = true, two = false },
    current_id = "one",
    diagnostics = { "kept by the caller" },
}, {
    available_width = 40,
    highlights = {},
})
assert(expanded_meta.count == 3)
assert(expanded[1].kind == "session")
assert(expanded[2].kind == "agent")
assert(expanded[2].parent_key == expanded[1].key)
assert(expanded[2].ordinal:find("a%-full%-path%-value"))
assert(expanded[3].kind == "session")
assert(expanded[3].expanded == false)

local collapsed = rows.build_active({
    sessions = { first },
    agents_by_id = { one = { { id = "agent", name = "agent" } } },
    expanded = { one = false },
}, { available_width = 40, highlights = {} })
assert(#collapsed == 1)
assert(collapsed[1].expandable)

local empty, empty_meta = rows.build_active({
    sessions = { first },
    agents_by_id = { one = {} },
    expanded = { one = true },
}, { available_width = 40, highlights = {} })
assert(#empty == 1)
assert(empty_meta.count == 1)
assert(empty[1].kind == "session")
assert(empty[1].expanded)

local narrow, metadata = rows.build({
    sessions = { first },
    marks_by_id = { one = "@one" },
}, {
    available_width = 10,
    highlights = {},
})
assert(metadata.count == 1)
assert(narrow[1].value.metadata.cwd == first.metadata.cwd)
assert(narrow[1].ordinal:find(first.metadata.cwd, 1, true))
assert(narrow[1].key == rows.session_key("one"))
