fixture.setup()

local _, _, session = require("sess.api").session.create(fixture.directory("hydration"))

local selected
package.loaded["telescope.actions"] = { close = function() end }
package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
        return selected
    end,
    get_current_picker = function()
        return _G.hydration_picker
    end,
}
package.loaded["telescope.config"] = {
    values = {
        generic_sorter = function() return {} end,
        selection_caret = "> ",
    },
}
package.loaded["telescope.finders"] = {
    new_table = function(value) return value end,
}
package.loaded["telescope.previewers"] = {
    new_buffer_previewer = function() return {} end,
}

local picker_instances = {}
package.loaded["telescope.pickers"] = {
    new = function(options)
        local prompt_bufnr = vim.api.nvim_create_buf(false, true)
        local results_bufnr = vim.api.nvim_create_buf(false, true)
        local prompt_win = vim.api.nvim_open_win(prompt_bufnr, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 20,
            height = 2,
        })
        local results_win = vim.api.nvim_open_win(results_bufnr, false, {
            relative = "editor",
            row = 3,
            col = 1,
            width = 20,
            height = 2,
        })
        local picker = {
            options = options,
            finder = options.finder,
            prompt_bufnr = prompt_bufnr,
            prompt_win = prompt_win,
            results_bufnr = results_bufnr,
            results_win = results_win,
            selection_caret = "> ",
            refresh_count = 0,
        }
        function picker:find() end
        function picker:refresh(finder)
            self.finder = finder
            self.refresh_count = self.refresh_count + 1
        end
        picker_instances[#picker_instances + 1] = picker
        return picker
    end,
}

local finders = require("telescope._extensions.sess.finders")
local hydration_callback
finders.generate_new_finder = function(_, callback)
    if callback then
        hydration_callback = callback
    end
    return { results = { { id = "base" } } }, callback and function() end or nil
end

local pickers = require("telescope._extensions.sess.pickers")
local actions = require("telescope._extensions.sess.actions")
local original_on_picker_close = actions.on_picker_close
local close_action_calls = 0
actions.on_picker_close = function(...)
    close_action_calls = close_action_calls + 1
    return original_on_picker_close(...)
end
-- Save the window callback too: an already queued close signal can outlive
-- deletion of its autocmd after the prompt's BufHidden signal.
local original_create_autocmd = vim.api.nvim_create_autocmd
local queued_window_close
vim.api.nvim_create_autocmd = function(event, options)
    if
        event == "WinClosed"
        and picker_instances[1]
        and options.pattern == tostring(picker_instances[1].prompt_win)
    then
        queued_window_close = queued_window_close or options.callback
    end
    return original_create_autocmd(event, options)
end
pickers.sess()
vim.api.nvim_create_autocmd = original_create_autocmd
local closed_picker = picker_instances[1]
local refreshes = closed_picker.refresh_count
assert(type(hydration_callback) == "function")
vim.api.nvim_exec_autocmds("BufHidden", { buffer = closed_picker.prompt_bufnr })
vim.api.nvim_exec_autocmds("WinClosed", { pattern = tostring(closed_picker.prompt_win) })
assert(type(queued_window_close) == "function")
queued_window_close()
assert(close_action_calls == 1, "duplicate close signals must run action cleanup only once")
assert(closed_picker._sess_picker_closed)
assert(not closed_picker._sess_action_pending)
actions.on_picker_close = original_on_picker_close
hydration_callback({ results = { { id = "late" } } }, nil, {})
assert(closed_picker.refresh_count == refreshes, "closed picker was refreshed")

pickers.sess()
local picker = picker_instances[2]
_G.hydration_picker = picker
local stale_callback = hydration_callback

-- Path input must stay synchronous and cheap. Directory completion already
-- filters filesystem rows, so it must not start an agent probe per keypress;
-- its session metadata index is reused while the prompt remains in path mode.
local api = require("sess.api")
local original_snapshot_async = api.active.snapshot_async
local original_directory_context = finders.directory_context
local context_calls = 0
finders.directory_context = function()
    context_calls = context_calls + 1
    return original_directory_context()
end
api.active.snapshot_async = function()
    error("path input must not probe agents")
end
local path_filter = picker.options.on_input_filter_cb
assert(type(path_filter) == "function")
assert(path_filter("./"))
assert(path_filter("./h"))
assert(context_calls == 1, "path metadata should be cached while typing")
api.active.snapshot_async = function(callback)
    callback({ agents_by_id = {}, diagnostics = {} })
    return function() end
end
assert(path_filter("sessions"))
api.active.snapshot_async = original_snapshot_async
finders.directory_context = original_directory_context

refreshes = picker.refresh_count
selected = { value = session }
require("telescope._extensions.sess.actions").toggle_pin_session(picker.prompt_bufnr)
assert(picker.refresh_count == refreshes + 1)
stale_callback({ results = { { id = "stale" } } }, nil, {})
assert(picker.refresh_count == refreshes + 1, "mutation hydration overwrote refreshed rows")

-- Regular hydration uses the same transaction as manual refresh. A partial
-- renderer mutation must retain the committed finder, manager, prompt, title,
-- expansion, and rendered rows.
local stable_finder = picker.finder
local stable_row = { value = { id = "stable" } }
picker.prompt = "stable prompt"
picker.prompt_title = "stable title"
picker._sess_active_snapshot = { token = "stable" }
picker._sess_expanded = { stable = true }
picker.manager = { entries = { stable_row } }
local stable_manager = picker.manager
local stable_snapshot = picker._sess_active_snapshot
local stable_expanded = picker._sess_expanded
local stable_pending = { finder = stable_finder, key = { id = "pending" }, opts = { parent = true } }
picker._sess_pending_selection_restore = stable_pending
picker._selection_entry = stable_row
picker._selection_row = 0
picker.layout = { prompt = { border = {
    title = "stable border title",
    change_title = function(self, title)
        self.title = title
    end,
} } }
picker.get_prompt = function(self)
    return self.prompt
end
picker.set_prompt = function(self, value)
    self.prompt = value
end
picker.get_selection = function()
    return { value = stable_row.value }
end
vim.api.nvim_buf_set_lines(picker.results_bufnr, 0, -1, false, { "stable rendered row" })
picker.refresh = function(self, finder)
    self.finder = finder
    self.manager.entries = { { value = { id = "candidate" } } }
    self.manager = { entries = {} }
    self.prompt = "candidate prompt"
    self.prompt_title = "candidate title"
    self.layout.prompt.border:change_title("candidate border title")
    self._sess_active_snapshot = { token = "candidate" }
    self._sess_expanded.stable = false
    self._sess_pending_selection_restore = nil
    self._selection_entry = { value = { id = "candidate" } }
    self._selection_row = 1
    vim.api.nvim_buf_set_lines(self.results_bufnr, 0, -1, false, { "candidate rendered row" })
    error("injected regular hydration failure")
end
hydration_callback({ results = { { id = "candidate" } } }, nil, { token = "candidate" })
assert(picker.finder == stable_finder)
local function assert_stable_rows()
    assert(picker.finder == stable_finder)
    assert(picker.manager == stable_manager)
    assert(picker.manager.entries[1] == stable_row)
    assert(picker.prompt == "stable prompt")
    assert(picker.prompt_title == "stable title")
    assert(picker.layout.prompt.border.title == "stable border title")
    assert(picker._sess_active_snapshot == stable_snapshot)
    assert(picker._sess_expanded == stable_expanded)
    assert(picker._sess_expanded.stable)
    assert(picker._sess_pending_selection_restore == stable_pending)
    assert(picker._selection_entry == stable_row)
    assert(picker._selection_row == 0)
    assert(not picker._sess_refreshing)
    assert(vim.api.nvim_buf_get_lines(picker.results_bufnr, 0, -1, false)[1] == "stable rendered row")
end
assert_stable_rows()

-- The data-independent resize refresh goes through the same rollback path.
vim.api.nvim_exec_autocmds("VimResized", {})
assert_stable_rows()

for _, item in ipairs(picker_instances) do
    if vim.api.nvim_win_is_valid(item.prompt_win) then
        vim.api.nvim_win_close(item.prompt_win, true)
    end
    if vim.api.nvim_win_is_valid(item.results_win) then
        vim.api.nvim_win_close(item.results_win, true)
    end
    if vim.api.nvim_buf_is_valid(item.prompt_bufnr) then
        vim.api.nvim_buf_delete(item.prompt_bufnr, { force = true })
    end
    if vim.api.nvim_buf_is_valid(item.results_bufnr) then
        vim.api.nvim_buf_delete(item.results_bufnr, { force = true })
    end
end
_G.hydration_picker = nil
