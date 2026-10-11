fixture.setup()

local api = require("sess.api")
local _, _, session = api.session.create(fixture.directory("project"))
local _, _, added_session = api.session.create(fixture.directory("new-project"))
local action_state = {
    selected = { value = { kind = "session", session_id = session.id } },
}
package.loaded["telescope.actions"] = {}
package.loaded["telescope.actions.state"] = action_state
package.loaded["telescope.finders"] = {
    new_table = function(value)
        return value
    end,
}
package.loaded["telescope.config"] = {
    values = {
        generic_sorter = function()
            return {}
        end,
    },
}

local actions = require("telescope._extensions.sess.actions")
local finders = require("telescope._extensions.sess.finders")
local layout = require("telescope._extensions.sess.layout")
local original_finder = finders.generate_active_finder_from_snapshot
local original_title = finders.active_dashboard_title
local original_width = layout.available_width
local original_result_width = layout.result_width
local old_snapshot = { title = "old", sessions = { session }, agents_by_id = {} }
local new_snapshot = { title = "new", sessions = { session, added_session }, agents_by_id = {} }
local old_row = { value = { kind = "session", session_id = session.id } }
local new_row = { value = { kind = "session", session_id = session.id } }
local added_row = { value = { kind = "session", session_id = added_session.id } }
local old_finder = { results = { old_row } }
local new_finder = { results = { new_row, added_row } }
local rendered_rows = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(rendered_rows, 0, -1, false, { "old rendered row" })
local old_manager = {
    entries = { old_row },
    num_results = function(self)
        return #self.entries
    end,
    get_entry = function(self, index)
        return self.entries[index]
    end,
}
local generated_expanded
local prompt_restores = 0

finders.generate_active_finder_from_snapshot = function(snapshot, expanded)
    generated_expanded = expanded
    return snapshot == new_snapshot and new_finder or old_finder
end
finders.active_dashboard_title = function(snapshot)
    return snapshot.title
end
layout.available_width = function()
    return 80
end
layout.result_width = function()
    return 60
end

local picker = {
    prompt_bufnr = 1,
    finder = old_finder,
    prompt_title = "old title",
    prompt = "search text",
    layout = {
        prompt = {
            border = {
                title = nil,
                change_title = function(self, title)
                    self.title = title
                end,
            },
        },
    },
    results_bufnr = rendered_rows,
    manager = old_manager,
    selected = old_row,
    _sess_expanded = { [session.id] = true },
    _sess_active_expand = "all",
    _sess_active_snapshot = old_snapshot,
    get_prompt = function(self)
        return self.prompt
    end,
    set_prompt = function(self, prompt)
        prompt_restores = prompt_restores + 1
        self.prompt = prompt
    end,
    get_selection = function(self)
        return self.selected
    end,
    set_selection = function(self, index)
        self.selected_index = index
        self.selected = self.finder.results[index]
    end,
}
action_state.get_current_picker = function()
    return picker
end
action_state.get_current_line = function()
    return picker.prompt
end
action_state.get_selected_entry = function()
    return action_state.selected
end

local pending_callback
local cancel_calls = 0
local original_snapshot_async = api.active.snapshot_async
api.active.snapshot_async = function(callback)
    pending_callback = callback
    return function()
        cancel_calls = cancel_calls + 1
    end
end

-- A refresh error must not replace the prompt, selection, expansion, title,
-- snapshot, or last usable rows, and its queued selection must be cancelled.
picker.refresh = function(self, finder, opts)
    self.refresh_opts = opts
    self.finder = finder
    self.prompt = "candidate search text"
    self.prompt_title = "candidate title"
    self.layout.prompt.border:change_title("candidate title")
    self.manager.entries = { new_row, added_row }
    vim.api.nvim_buf_set_lines(self.results_bufnr, 0, -1, false, { "candidate rendered row" })
    error("injected picker refresh failure")
end
actions.refresh_active(1)
assert(picker._sess_action_pending)
pending_callback(new_snapshot)
assert(picker.finder == old_finder)
assert(picker.manager == old_manager)
assert(picker.manager.entries[1] == old_row)
assert(vim.api.nvim_buf_get_lines(rendered_rows, 0, -1, false)[1] == "old rendered row")
assert(picker.selected == old_row)
assert(picker.prompt_title == "old title")
assert(picker.layout.prompt.border.title == nil)
assert(picker.prompt == "search text")
assert(prompt_restores == 1, "failed refresh must restore input through set_prompt")
assert(picker._sess_active_snapshot == old_snapshot)
assert(picker._sess_expanded[session.id] == true)
assert(picker._sess_pending_selection_restore == nil)
assert(not picker._sess_action_pending)
assert(picker._sess_active_refresh_cancel == nil)
assert(picker.refresh_opts.reset_prompt == false)

-- Fakes without Telescope's prompt APIs still restore the field, including an
-- empty prompt rather than mistaking it for missing state.
local set_prompt = picker.set_prompt
local get_prompt = picker.get_prompt
local get_current_line = action_state.get_current_line
picker.get_prompt = nil
picker.set_prompt = nil
action_state.get_current_line = nil
picker.prompt = ""
actions.refresh_active(1)
pending_callback(new_snapshot)
assert(picker.prompt == "")
assert(picker.finder == old_finder)
assert(picker.manager.entries[1] == old_row)
assert(not picker._sess_action_pending)
picker.get_prompt = get_prompt

-- Manual refresh remains available when an empty picker has no selection key.
local empty_snapshot = { title = "empty", sessions = {}, agents_by_id = {} }
local empty_finder = { results = {} }
finders.generate_active_finder_from_snapshot = function(snapshot)
    if snapshot == empty_snapshot then
        return empty_finder
    end
    return old_finder
end
picker.finder = empty_finder
picker.manager.entries = {}
picker.selected = nil
picker.prompt = "empty search"
action_state.selected = nil
picker.refresh = function(self, finder, opts)
    self.refresh_opts = opts
    self.finder = finder
end
actions.refresh_active(1)
pending_callback(empty_snapshot)
assert(picker.finder == empty_finder)
assert(picker._sess_active_snapshot == empty_snapshot)
assert(picker.prompt == "empty search")
assert(not picker._sess_action_pending)
finders.generate_active_finder_from_snapshot = function(snapshot, expanded)
    generated_expanded = expanded
    return snapshot == new_snapshot and new_finder or old_finder
end
picker.finder = old_finder
picker.manager.entries = { old_row }
picker.selected = old_row
picker.prompt = "search text"
picker._sess_active_snapshot = old_snapshot
picker.prompt_title = "old title"
action_state.selected = { value = { kind = "session", session_id = session.id } }
picker.get_prompt = get_prompt
picker.set_prompt = set_prompt
action_state.get_current_line = get_current_line
picker.prompt = "search text"

-- Generator failures take the same cleanup path and preserve the committed view.
finders.generate_active_finder_from_snapshot = function()
    error("injected finder generation failure")
end
actions.refresh_active(1)
pending_callback(new_snapshot)
assert(picker.finder == old_finder)
assert(picker.manager == old_manager)
assert(picker.manager.entries[1] == old_row)
assert(vim.api.nvim_buf_get_lines(rendered_rows, 0, -1, false)[1] == "old rendered row")
assert(picker.selected == old_row)
assert(picker.prompt_title == "old title")
assert(picker._sess_active_snapshot == old_snapshot)
assert(picker._sess_pending_selection_restore == nil)
assert(not picker._sess_action_pending)

-- A successful refresh commits the candidate only after refresh and selection
-- restoration have completed.
finders.generate_active_finder_from_snapshot = original_finder
picker.refresh = function(self, finder, opts)
    self.refresh_opts = opts
    self.finder = finder
end
finders.generate_active_finder_from_snapshot = function(snapshot, expanded)
    generated_expanded = expanded
    return new_finder
end
actions.refresh_active(1)
pending_callback(new_snapshot)
assert(picker.finder == new_finder)
assert(picker.prompt_title == "new")
assert(picker._sess_active_snapshot == new_snapshot)
assert(picker.selected_index == 1)
assert(generated_expanded[session.id] == true)
assert(not picker._sess_action_pending)
assert(picker.selected.value.session_id == session.id)

-- A polling generation that commits while manual hydration is pending owns
-- the picker; the stale manual callback must not regress its committed view.
actions.refresh_active(1)
local manual_generation = picker._sess_active_refresh_generation
picker._sess_active_refresh_generation = manual_generation + 1
picker.finder = new_finder
picker._sess_active_snapshot = new_snapshot
picker.prompt_title = "new"
pending_callback(old_snapshot)
assert(picker.finder == new_finder)
assert(picker._sess_active_snapshot == new_snapshot)
assert(picker.prompt_title == "new")
assert(not picker._sess_action_pending)

-- Expansion is committed only after the candidate finder is accepted. A
-- failed refresh leaves the old expansion table and selected session intact.
local committed_expanded = picker._sess_expanded
picker.refresh = function(self, finder, opts)
    self.refresh_opts = opts
    self.finder = finder
    error("injected expansion refresh failure")
end
actions.toggle_active(1)
assert(generated_expanded ~= committed_expanded)
assert(generated_expanded[session.id] == false)
assert(picker._sess_expanded == committed_expanded)
pending_callback(new_snapshot)
assert(picker._sess_expanded == committed_expanded)
assert(picker.finder == new_finder)
assert(picker.selected.value.session_id == session.id)

picker.refresh = function(self, finder, opts)
    self.refresh_opts = opts
    self.finder = finder
end
actions.toggle_active(1)
pending_callback(new_snapshot)
assert(picker._sess_expanded ~= committed_expanded)
assert(picker._sess_expanded[session.id] == false)
assert(picker._sess_active_snapshot == new_snapshot)
assert(picker.selected.value.session_id == session.id)

-- Closing while hydration is pending cancels the handle and releases every
-- action/selection guard, even if the async callback never runs.
actions.refresh_active(1)
assert(picker._sess_action_pending)
assert(type(picker._sess_active_refresh_cancel) == "function")
actions.on_picker_close(picker)
assert(cancel_calls == 1)
assert(picker._sess_active_refresh_cancel == nil)
assert(picker._sess_pending_selection_restore == nil)
assert(not picker._sess_action_pending)
pending_callback = nil

-- Focusing an agent reports its own completion after the API result is
-- recorded. Non-fatal diagnostics must remain visible alongside that label.
local original_focus = api.agent.focus
local original_current = api.state.current
api.state.current = function()
    return session
end
action_state.get_selected_entry = function()
    return { value = { kind = "agent", session_id = session.id, agent_id = "pi" } }
end
api.agent.focus = function()
    return true, nil, nil, { "focus diagnostic" }
end
picker._sess_action_status = nil
actions.focus_agent(1)
assert(picker._sess_action_status == "Done with diagnostics")
api.agent.focus = original_focus
api.state.current = original_current

-- The active picker must install the same close lifecycle contract as regular
-- and restore pickers. Exercise the registered autocmd rather than invoking
-- actions.on_picker_close directly. Multiple Telescope close signals must
-- still reach the lifecycle action exactly once.
local original_on_picker_close = actions.on_picker_close
local close_action_calls = 0
actions.on_picker_close = function(...)
    close_action_calls = close_action_calls + 1
    return original_on_picker_close(...)
end
local active_refresh_module = package.loaded["sess.ui.active_refresh"]
package.loaded["sess.ui.active_refresh"] = { start = function() end }
package.loaded["telescope.previewers"] = {
    new_buffer_previewer = function()
        return {}
    end,
}
local hook_prompt = vim.api.nvim_create_buf(false, true)
local hook_results = vim.api.nvim_create_buf(false, true)
local hook_prompt_win = vim.api.nvim_open_win(hook_prompt, false, {
    relative = "editor",
    row = 1,
    col = 1,
    width = 20,
    height = 2,
})
local hook_results_win = vim.api.nvim_open_win(hook_results, false, {
    relative = "editor",
    row = 3,
    col = 1,
    width = 20,
    height = 2,
})
local hook_picker
package.loaded["telescope.pickers"] = {
    new = function(options)
        hook_picker = {
            finder = options.finder,
            prompt_bufnr = hook_prompt,
            prompt_win = hook_prompt_win,
            results_bufnr = hook_results,
            results_win = hook_results_win,
            layout = { prompt = { border = {} } },
        }
        function hook_picker:find() end
        function hook_picker:refresh(finder)
            self.finder = finder
        end
        function hook_picker:register_completion_callback(callback)
            self.completion_callback = callback
        end
        function hook_picker:set_selection(index)
            self.selected_index = index
        end
        return hook_picker
    end,
}
local hook_cancel_calls = 0
api.active.snapshot_async = function()
    return function()
        hook_cancel_calls = hook_cancel_calls + 1
    end
end
action_state.get_current_picker = function()
    return hook_picker
end
action_state.get_selected_entry = function()
    return { value = { kind = "session", session_id = session.id } }
end
require("telescope._extensions.sess.pickers").active({ previewer = false })
actions.refresh_active(1)
assert(hook_picker._sess_action_pending)
vim.api.nvim_exec_autocmds("BufHidden", { buffer = hook_prompt })
vim.api.nvim_exec_autocmds("WinClosed", { pattern = tostring(hook_prompt_win) })
assert(close_action_calls == 1)
assert(hook_cancel_calls == 1)
assert(hook_picker._sess_active_refresh_cancel == nil)
assert(hook_picker._sess_pending_selection_restore == nil)
assert(not hook_picker._sess_action_pending)
assert(hook_picker._sess_picker_closed)
if vim.api.nvim_win_is_valid(hook_prompt_win) then
    vim.api.nvim_win_close(hook_prompt_win, true)
end
if vim.api.nvim_win_is_valid(hook_results_win) then
    vim.api.nvim_win_close(hook_results_win, true)
end
if vim.api.nvim_buf_is_valid(hook_prompt) then
    vim.api.nvim_buf_delete(hook_prompt, { force = true })
end
if vim.api.nvim_buf_is_valid(hook_results) then
    vim.api.nvim_buf_delete(hook_results, { force = true })
end
package.loaded["sess.ui.active_refresh"] = active_refresh_module
actions.on_picker_close = original_on_picker_close
vim.api.nvim_buf_delete(rendered_rows, { force = true })

api.active.snapshot_async = original_snapshot_async
finders.generate_active_finder_from_snapshot = original_finder
finders.active_dashboard_title = original_title
layout.available_width = original_width
layout.result_width = original_result_width
