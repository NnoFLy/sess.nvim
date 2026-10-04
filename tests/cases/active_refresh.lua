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
assert(vim.wait(500, function() return retry_calls >= 2 end, 10))
assert(retry_picker.finder ~= nil, "retry should leave picker usable")
stop_retry()
vim.api.nvim_buf_delete(retry_prompt, { force = true })

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
