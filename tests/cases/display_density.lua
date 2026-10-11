fixture.setup()

package.loaded["telescope.actions"] = { close = function() end }
package.loaded["telescope.actions.state"] = {}
package.loaded["telescope.finders"] = {
    new_table = function(options)
        return options
    end,
}
package.loaded["telescope.config"] = {
    values = { generic_sorter = function() end },
}

local config = require("telescope._extensions.sess.config")
local layout = require("telescope._extensions.sess.layout")
local finders = require("telescope._extensions.sess.finders")

assert(not pcall(config.setup, { display = { mode = "wide" } }))
assert(not pcall(config.setup, { display = { compact_width = 0 } }))
assert(not pcall(config.setup, { display = { icons = "yes" } }))
assert(not pcall(config.setup, { display = { ascii_fallback = "yes" } }))
assert(not pcall(config.setup, { display = { toggle_key = 1 } }))
assert(not pcall(config.setup, { display = { toggle_key = "" } }))
assert(layout.display_mode({ mode = "auto", compact_width = 100 }, 99) == "compact")
assert(layout.display_mode({ mode = "auto", compact_width = 100 }, 100) == "detailed")
vim.cmd("vnew")
local results_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_width(results_win, 37)
assert(layout.result_width({ results_win = results_win }) == 37)
vim.api.nvim_win_close(results_win, true)

local session = {
    id = "density",
    metadata = {
        name = "density-session",
        cwd = "/projects/density",
        pinned = true,
    },
}
local compact = finders.format_session_display(session, {
    mark = "@d",
    display = {
        mode = "compact",
        available_width = 80,
        path_style = "full",
        highlights = {},
    },
})
assert(compact:find("density%-session"))
assert(compact:find("/projects/density", 1, true))
assert(compact:find("@d", 1, true))
assert(compact:find("★", 1, true))

local detailed = finders.format_session_display(session, {
    display = {
        mode = "detailed",
        available_width = 80,
        path_style = "full",
        highlights = {},
    },
})
assert(detailed:find("★", 1, true))

local ascii = finders.format_session_display(session, {
    display = {
        mode = "compact",
        icons = false,
        available_width = 80,
        path_style = "full",
        highlights = {},
    },
})
assert(not ascii:find("★", 1, true))
assert(ascii:find(".", 1, true))

local dashboard_snapshot = { sessions = {}, agents_by_id = {} }
config.setup({ display = { icons = false, ascii_fallback = false } })
assert(
    finders.active_dashboard_title(dashboard_snapshot)
        == "ACTIVE SESSIONS | 0 sessions | 0 agents"
)
config.setup({ display = { icons = true, ascii_fallback = true } })
assert(
    finders.active_dashboard_title(dashboard_snapshot)
        == "ACTIVE SESSIONS | 0 sessions | 0 agents"
)

local rows = finders.build_active_entries(
    { session },
    {},
    {},
    nil,
    {},
    {},
    nil,
    {
        mode = "compact",
        available_width = 40,
        result_width = 40,
        highlights = {},
    }
)
assert(#rows == 1)
assert(rows[1].display:find("density-session", 1, true))
assert(rows[1].ordinal:find("/projects/density", 1, true))
assert(rows[1].session.metadata.cwd == "/projects/density")
