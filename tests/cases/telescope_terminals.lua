fixture.setup()
local selected
local picker = { _sess_expanded = {}, _sess_active_expand = "all" }
package.loaded["telescope.actions"] = { close = function() end }
package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
        return selected
    end,
    get_current_picker = function()
        return picker
    end,
}
package.loaded["telescope.finders"] = {
    new_table = function(value)
        return value
    end,
}
package.loaded["telescope.config"] = { values = { generic_sorter = function() end } }
local notifications = {}
vim.notify = function(message, level)
    notifications[#notifications + 1] = { message, level }
end
local api = require("sess.api")
local rows = require("sess.ui.rows")
local finders = require("telescope._extensions.sess.finders")
local actions = require("telescope._extensions.sess.actions")
local selection = require("telescope._extensions.sess.selection")
local search = require("sess.ui.search")
local background = rows.key("background_terminals", "")
local snapshot = {
    sessions = { { id = "active", metadata = { name = "Zebra", cwd = "/project" } } },
    agents_by_id = {},
    marks_by_id = {},
    terminals = {
        {
            id = "full:execution:identity",
            owner_id = "inactive",
            owner_name = "Alpha owner",
            name = "Alpha server",
            execution_state = "running",
            available = true,
        },
        { id = "ownerless", name = "shell", execution_state = "completed", available = true },
    },
}
picker._sess_active_snapshot = snapshot
picker.finder = finders.generate_active_finder_from_snapshot(snapshot, picker._sess_expanded, "all")
assert(#picker.finder.results == 4)
assert(picker._sess_expanded[background])
local terminal = picker.finder.results[3]
assert(terminal.id == "full:execution:identity")
-- Actual Telescope scoring must leave the background after active sessions,
-- even when its name would win fuzzy sorting. Full identity and owner search work.
local sorter = search.new_active_sorter({
    scoring_function = function()
        return 1
    end,
})
local function score(prompt, row)
    return sorter.scoring_function(prompt, picker.finder.entry_maker(row))
end
assert(score("", picker.finder.results[1]) < score("", terminal))
assert(score("full:execution:identity", terminal) >= 0)
assert(score("Alpha owner", terminal) >= 0)
assert(score("missing", terminal) < 0)
local refreshes = 0
picker.refresh = function(self, finder)
    self.finder = finder
    refreshes = refreshes + 1
end
picker.set_selection = function(self, index)
    self.selected_index = index
end
selected = { value = terminal }
actions.toggle_active(1)
assert(refreshes == 1 and not picker._sess_expanded[background])
assert(
    picker.selected_index == 2,
    "collapsed terminal selection must fall back to background header"
)
selected = { value = picker.finder.results[2] }
actions.active_enter(1)
assert(picker._sess_expanded[background], "background Enter only expands")
actions.active_enter(1)
assert(picker._sess_expanded[background], "expanded background Enter must not collapse")
local focuses = {}
api.terminal.focus = function(id)
    focuses[#focuses + 1] = id
    actions.active_enter(1) -- pending guard rejects reentrancy
    return true, nil, {}, { "focus diagnostic" }
end
api.session.load = function()
    error("terminal selection must delegate owner lifecycle to focus")
end
vim.ui.input = function()
    error("terminal/group is not a session mutation target")
end
api.session.toggle_pin = function()
    error("terminal/group is not a session mutation target")
end
for _, row in ipairs(picker.finder.results) do
    if row.kind == "terminal" or row.kind == "background_terminals" then
        selected = { value = row }
        actions.rename_session(1)
        actions.toggle_pin_session(1)
        actions.delete_session(1)
        actions.unload_session(1)
        if row.kind == "terminal" then
            actions.active_enter(1)
        end
    end
end
assert(vim.deep_equal(focuses, { "full:execution:identity", "ownerless" }))
assert(not picker._sess_action_pending)
selected = { value = terminal }
api.terminal.focus = function()
    error("focus exception")
end
actions.active_enter(1)
assert(not picker._sess_action_pending)
local warned, errored = false, false
for _, notification in ipairs(notifications) do
    warned = warned
        or (
            notification[1]:find("focus diagnostic", 1, true) ~= nil
            and notification[2] == vim.log.levels.WARN
        )
    errored = errored
        or (
            notification[1]:find("focus exception", 1, true) ~= nil
            and notification[2] == vim.log.levels.ERROR
        )
end
assert(warned and errored, "success diagnostics and exceptions must be distinguishable")
-- Closing the real picker hook cannot release the in-flight focus guard;
-- late acceptance from that closed picker is rejected.
package.loaded["telescope.actions"].close = function()
    actions.on_picker_close(picker)
end
local close_focuses = 0
api.terminal.focus = function()
    close_focuses = close_focuses + 1
    actions.active_enter(1)
    return true, nil, {}, {}
end
actions.active_enter(1)
actions.active_enter(1)
assert(close_focuses == 1 and not picker._sess_action_pending)
selected = { value = picker.finder.results[2] }
picker._sess_expanded[background] = false
actions.active_enter(1)
assert(
    not picker._sess_expanded[background],
    "late background acceptance cannot refresh a closed picker"
)
picker._sess_picker_closed = nil
-- Selection uses the execution alone when ownership/grouping changes.
snapshot.sessions[#snapshot.sessions + 1] = { id = "inactive", metadata = { name = "Alpha owner" } }
local moved = finders.generate_active_finder_from_snapshot(
    snapshot,
    { inactive = true, [background] = true },
    "none"
)
assert(selection.restore(picker, moved, selection.key(terminal), { parent = true }))
assert(moved.results[picker.selected_index].id == "full:execution:identity")
local collapsed = finders.generate_active_finder_from_snapshot(snapshot, {}, "none")
local moved_terminal = moved.results[picker.selected_index]
selection.restore(picker, collapsed, selection.key(moved_terminal), { parent = true })
assert(collapsed.results[picker.selected_index].session_id == "inactive")
-- A terminal that moves into a collapsed owner still selects that owner,
-- rather than an unrelated first session or the old background group.
selection.restore(picker, collapsed, selection.key(terminal), { parent = true })
assert(collapsed.results[picker.selected_index].session_id == "inactive")
local help = require("telescope._extensions.sess.help")
local visible = help.entries("active", "n", {
    n = {
        ["<CR>"] = actions.active_enter,
        ["<Tab>"] = actions.toggle_active,
        rr = actions.rename_session,
        dd = actions.delete_session,
    },
}, {}, terminal)
assert(#visible == 2, "terminal help offers focus/expansion, not session mutations")

-- A remembered background expansion must not invert toggle-all when that
-- group no longer exists and every visible session is collapsed.
picker._sess_active_snapshot =
    { sessions = { snapshot.sessions[1] }, terminals = {}, agents_by_id = {}, marks_by_id = {} }
picker._sess_expanded = { active = false, [background] = true }
picker.finder = finders.generate_active_finder_from_snapshot(
    picker._sess_active_snapshot,
    picker._sess_expanded,
    "all"
)
actions.toggle_all_active(1)
assert(picker._sess_expanded.active, "toggle-all considers visible groups, not vanished background")

-- Terminal controls are presentation-only escapes, never rewritten search/action data.
local labels = finders.generate_active_finder_from_snapshot({
    sessions = {},
    terminals = {
        {
            id = "full\nidentity",
            name = "Label\nserver\t",
            owner_id = "inactive",
            owner_name = "Owner\nproject\r",
            execution_state = "running\t",
            available = true,
        },
    },
}, {}, "all")
local label = labels.results[2]
assert(not label.display:find("[%c]"))
assert(label.display:find("Label server ", 1, true))
assert(label.display:find("Owner project ", 1, true))
assert(label.display:find("running  available", 1, true))
assert(label.ordinal:find("Owner\nproject\r", 1, true))
assert(label.ordinal:find("Label\nserver\t", 1, true))
fixture.equal("full\nidentity", label.terminal_id)
fixture.equal("Owner\nproject\r", label.value.owner_name)
