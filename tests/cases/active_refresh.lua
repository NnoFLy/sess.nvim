fixture.setup()

local api = require("sess.api")
local _, _, session = api.session.create(fixture.directory("project"))
local terminal = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, terminal)
local channel = vim.api.nvim_open_term(terminal, {})
vim.b[terminal].terminal_job_id = 99
vim.fn.job_info = function()
    return { status = "run", cmd = { "pi" } }
end

package.loaded["telescope.finders"] = {
    new_table = function(value)
        return value
    end,
}

local sync_generate = require("telescope._extensions.sess.finders").generate_active_finder
local expanded = { [session.id] = true }
local finder, rows = sync_generate(expanded)
local function generate(expanded_by_id, done)
    vim.schedule(function()
        local next_finder, next_rows = sync_generate(expanded_by_id)
        done(next_finder, next_rows)
    end)
end
local prompt = vim.api.nvim_create_buf(false, true)
local win = vim.api.nvim_open_win(prompt, true, {
    relative = "editor", row = 1, col = 1, width = 20, height = 4,
})
local refreshes = 0
local picker = {
    prompt_bufnr = prompt,
    prompt_win = win,
    _sess_expanded = expanded,
    finder = finder,
    selected_value = rows[2].value or rows[2],
    get_selection = function(self)
        return { value = self.selected_value }
    end,
    set_selection = function(self, index)
        self.selected_index = index
        self.selected_value = self.finder.results[index].value or self.finder.results[index]
    end,
    refresh = function(self, next_finder, opts)
        assert(opts.reset_prompt == false)
        refreshes = refreshes + 1
        self.finder = next_finder
    end,
}
local stop = require("sess.ui.active_refresh").start(picker, generate, rows, 100)
assert(stop)

vim.api.nvim_chan_send(channel, "\27[2J\27[HWorking...")
assert(vim.wait(2000, function()
    return picker.finder.results[2].display:find("working", 1, true)
end, 10), "picker did not refresh after terminal output")
assert(picker.selected_index == 2)
assert(picker.selected_value.kind == "agent")
assert(picker.selected_value.agent_id == rows[2].agent_id)
local before = refreshes
vim.wait(600, function() return false end, 10)
assert(refreshes == before, "unchanged rows must not redraw")

vim.api.nvim_chan_send(channel, "\27[2J\27[HReady")
assert(vim.wait(2000, function()
    return picker.finder.results[2].display:find("idle", 1, true)
end, 10))

-- Hidden sessions must continue to update even when their windows are closed.
vim.api.nvim_win_close(win, true)
assert(api.session.create(fixture.directory("other")))
local _, _, hidden = api.agent.list(session.id)
assert(hidden[1].status == "idle")
vim.api.nvim_chan_send(channel, "\27[2J\27[HWorking...")
assert(vim.wait(1000, function()
    local _, _, agents = api.agent.list(session.id)
    return agents[1].status == "working"
end, 10))

before = refreshes
vim.wait(600, function() return false end, 10)
assert(refreshes == before, "closed picker must stop refreshing")
stop() -- Cleanup is idempotent, including callbacks already queued.

-- Selection restoration waits for Telescope's finder completion callback. A
-- direct set_selection immediately after refresh can target the old manager.
local selection = require("telescope._extensions.sess.selection")
local completion
local completion_picker = {
    finder = { results = { { kind = "agent", session_id = "one", agent_id = "pi" } } },
    register_completion_callback = function(_, callback)
        completion = callback
    end,
    set_selection = function(self, index)
        self.selected_index = index
    end,
}
assert(selection.attach(completion_picker))
selection.queue(completion_picker, completion_picker.finder, {
    kind = "agent",
    session_id = "one",
    agent_id = "pi",
})
assert(completion_picker.selected_index == nil)
completion()
assert(completion_picker.selected_index == 1)

-- Telescope's manager is sorted independently of finder.results, and set_selection
-- expects a zero-based display row. Restore by manager position to avoid jumps.
local manager_picker = {
    manager = {
        entries = {
            { value = { id = "first" } },
            { value = { id = "selected" } },
        },
        num_results = function(self)
            return #self.entries
        end,
        get_entry = function(self, index)
            return self.entries[index]
        end,
    },
    get_row = function(_, index)
        return index - 1
    end,
    set_selection = function(self, row)
        self.selected_row = row
    end,
}
assert(selection.restore(manager_picker, { results = {} }, { id = "selected" }))
assert(manager_picker.selected_row == 1)

-- A failed best-effort probe keeps the dashboard alive so a later poll can
-- recover instead of closing the picker.
local retry_prompt = vim.api.nvim_create_buf(false, true)
local retry_calls = 0
local retry_finder, retry_rows = sync_generate(expanded)
local retry_picker = {
    prompt_bufnr = retry_prompt,
    _sess_expanded = expanded,
    _sess_active_snapshot = require("sess.api").active.initial_snapshot(),
    finder = retry_finder,
    refresh = function(self, next_finder)
        self.finder = next_finder
    end,
}
local stop_retry = require("sess.ui.active_refresh").start(
    retry_picker,
    function(expanded_by_id, done)
        retry_calls = retry_calls + 1
        if retry_calls == 1 then
            error("probe failed")
        end
        return sync_generate(expanded_by_id)
    end,
    retry_rows,
    20
)
assert(stop_retry)
assert(
    vim.wait(500, function()
        return retry_picker._sess_active_refresh_warning ~= nil
    end, 10),
    "failed probes should expose a textual warning"
)
assert(vim.wait(500, function() return retry_calls >= 2 end, 10))
assert(retry_picker.finder ~= nil, "retry should leave picker usable")
assert(retry_picker._sess_active_refresh_warning == nil, "successful retry should clear warning")
stop_retry()
vim.api.nvim_buf_delete(retry_prompt, { force = true })

-- A synchronous generator keeps its snapshot as well as its finder and rows;
-- otherwise identical rows can leave the dashboard title and cache stale.
local sync_snapshot_prompt = vim.api.nvim_create_buf(false, true)
local sync_snapshot_old = { token = "old" }
local sync_snapshot_new = { token = "new" }
local sync_snapshot_finder = { results = { { value = { id = "old" } } } }
local sync_snapshot_next_finder = { results = { { value = { id = "new" } } } }
local sync_snapshot_picker = {
    prompt_bufnr = sync_snapshot_prompt,
    finder = sync_snapshot_finder,
    _sess_active_snapshot = sync_snapshot_old,
    refresh = function(self, next_finder)
        self.finder = next_finder
    end,
}
local stop_sync_snapshot = require("sess.ui.active_refresh").start(
    sync_snapshot_picker,
    function()
        return sync_snapshot_next_finder, sync_snapshot_next_finder.results, sync_snapshot_new
    end,
    sync_snapshot_finder.results,
    1000
)
assert(sync_snapshot_picker._sess_active_snapshot == sync_snapshot_new)
assert(sync_snapshot_picker.finder == sync_snapshot_next_finder)
stop_sync_snapshot()
vim.api.nvim_buf_delete(sync_snapshot_prompt, { force = true })

-- Automatic refresh is transactional even when Telescope mutates several
-- fields before reporting a partial refresh failure.
local transaction_prompt = vim.api.nvim_create_buf(false, true)
local transaction_results = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(transaction_results, 0, -1, false, { "old rendered row" })
local transaction_row = { value = { kind = "session", session_id = "transaction" } }
local transaction_next_row = { value = { kind = "session", session_id = "next" } }
local transaction_finder = { results = { transaction_row } }
local transaction_next_finder = { results = { transaction_next_row } }
local transaction_manager = {
    entries = { transaction_row },
    num_results = function(self)
        return #self.entries
    end,
    get_entry = function(self, index)
        return self.entries[index]
    end,
}
local transaction_snapshot = { token = "old" }
local transaction_next_snapshot = { token = "new" }
local transaction_expanded = { transaction = true }
local transaction_selection = transaction_row
local transaction_picker = {
    prompt_bufnr = transaction_prompt,
    finder = transaction_finder,
    manager = transaction_manager,
    prompt = "old prompt",
    prompt_title = "old title",
    results_bufnr = transaction_results,
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
    _sess_expanded = transaction_expanded,
    _sess_active_snapshot = transaction_snapshot,
    get_prompt = function(self)
        return self.prompt
    end,
    set_prompt = function(self, prompt)
        self.prompt = prompt
    end,
    get_selection = function()
        return transaction_selection
    end,
    get_reset_row = function()
        return 0
    end,
    set_selection = function(self, row)
        self.selected_row = row
    end,
    refresh = function(self, finder)
        self.finder = finder
        self.manager.entries = { transaction_next_row }
        self.prompt = "candidate prompt"
        self.prompt_title = "candidate title"
        self.layout.prompt.border:change_title("candidate title")
        self._sess_expanded.transaction = false
        vim.api.nvim_buf_set_lines(self.results_bufnr, 0, -1, false, { "candidate rendered row" })
        error("injected automatic refresh failure")
    end,
}
local stop_transaction = require("sess.ui.active_refresh").start(
    transaction_picker,
    function()
        return transaction_next_finder, transaction_next_finder.results, transaction_next_snapshot
    end,
    transaction_finder.results,
    1000
)
assert(stop_transaction)
assert(transaction_picker.finder == transaction_finder)
assert(transaction_picker.manager.entries[1] == transaction_row)
assert(transaction_picker.prompt == "old prompt")
assert(transaction_picker.prompt_title == "old title")
assert(transaction_picker.layout.prompt.border.title == nil)
assert(transaction_picker._sess_active_snapshot == transaction_snapshot)
assert(transaction_picker._sess_expanded == transaction_expanded)
assert(transaction_picker._sess_expanded.transaction)
assert(vim.api.nvim_buf_get_lines(transaction_results, 0, -1, false)[1] == "old rendered row")
assert(transaction_picker._sess_active_refresh_warning ~= nil)
stop_transaction()
vim.api.nvim_buf_delete(transaction_prompt, { force = true })
vim.api.nvim_buf_delete(transaction_results, { force = true })

-- Reconciliation must not leave a vanished agent selected.
local reconcile_prompt = vim.api.nvim_create_buf(false, true)
local reconcile_selection = {
    value = { kind = "agent", session_id = "session", agent_id = "gone" },
}
local reconcile_set_index
local reconcile_picker = {
    prompt_bufnr = reconcile_prompt,
    finder = { results = { reconcile_selection.value } },
    get_selection = function()
        return reconcile_selection
    end,
    set_selection = function(self, index)
        reconcile_set_index = index
        reconcile_selection = { value = { kind = "session", session_id = "session" } }
    end,
    refresh = function(self, finder)
        self.finder = finder
    end,
}
local reconcile_finder = { results = { reconcile_selection.value } }
local reconcile_next = { results = { { kind = "session", session_id = "session" } } }
local stop_reconcile = require("sess.ui.active_refresh").start(
    reconcile_picker,
    function()
        return reconcile_next, reconcile_next.results
    end,
    reconcile_finder.results,
    1000
)
assert(stop_reconcile)
assert(reconcile_set_index == 1)
stop_reconcile()
vim.api.nvim_buf_delete(reconcile_prompt, { force = true })

-- A resize arriving during an async hydration must be replayed after it
-- completes, so rows are regenerated for the new result width.
local pending_prompt = vim.api.nvim_create_buf(false, true)
local pending_calls = 0
local pending_done
local pending_picker = {
    prompt_bufnr = pending_prompt,
    _sess_expanded = expanded,
    finder = { results = {} },
    refresh = function(self, finder)
        self.finder = finder
    end,
}
local stop_pending = require("sess.ui.active_refresh").start(
    pending_picker,
    function(_, done)
        pending_calls = pending_calls + 1
        pending_done = done
    end,
    {},
    1000
)
assert(stop_pending)
assert(pending_calls == 1)
vim.api.nvim_exec_autocmds("VimResized", {})
assert(pending_calls == 1)
pending_done({}, {}, nil)
assert(vim.wait(500, function() return pending_calls == 2 end, 10))
pending_done({}, {}, nil)
stop_pending()
vim.api.nvim_buf_delete(pending_prompt, { force = true })

-- Active rows are regenerated at the result width after a resize, including
-- the compact hierarchy indentation used by narrow dashboards.
local active_finders = require("telescope._extensions.sess.finders")
local resize_snapshot = {
    sessions = { session },
    agents_by_id = {
        [session.id] = {
            {
                id = "resize-agent",
                name = "long-child-name",
                status = "working",
                info = "verbose child information",
            },
        },
    },
    focused_by_id = {},
    marks_by_id = {},
    marks_loaded = true,
    agents_loaded_by_id = { [session.id] = true },
    stale_by_id = {},
    current_id = nil,
    diagnostics = {},
}
local resize_expanded = { [session.id] = true }
local resize_width = 60
local resize_finder, resize_rows = active_finders.generate_active_finder_from_snapshot(
    resize_snapshot,
    resize_expanded,
    "all",
    { available_width = resize_width }
)
assert(resize_rows[2].display:find("  └─", 1, true))
assert(vim.fn.strdisplaywidth(resize_rows[2].display) <= resize_width)
local resize_prompt = vim.api.nvim_create_buf(false, true)
local resize_picker = {
    prompt_bufnr = resize_prompt,
    _sess_expanded = resize_expanded,
    _sess_active_snapshot = resize_snapshot,
    finder = resize_finder,
    refresh = function(self, next_finder)
        self.finder = next_finder
    end,
}
local stop_resize = require("sess.ui.active_refresh").start(
    resize_picker,
    function(expanded_by_id, done)
        local next_finder, next_rows = active_finders.generate_active_finder_from_snapshot(
            resize_snapshot,
            expanded_by_id,
            "all",
            { available_width = resize_width }
        )
        done(next_finder, next_rows, resize_snapshot)
    end,
    resize_rows,
    1000
)
assert(stop_resize)
resize_width = 20
vim.api.nvim_exec_autocmds("VimResized", {})
local narrow_child = resize_picker.finder.results[2]
assert(vim.fn.strdisplaywidth(narrow_child.display) <= resize_width)
assert(narrow_child.display:find("└─", 1, true))
assert(not narrow_child.display:find("  └─", 1, true))
stop_resize()
vim.api.nvim_buf_delete(resize_prompt, { force = true })
