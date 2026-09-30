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

local generate = require("telescope._extensions.sess.finders").generate_active_finder
local expanded = { [session.id] = true }
local finder, rows = generate(expanded)
local prompt = vim.api.nvim_create_buf(false, true)
local win = vim.api.nvim_open_win(prompt, true, {
    relative = "editor", row = 1, col = 1, width = 20, height = 4,
})
local refreshes = 0
local picker = {
    prompt_bufnr = prompt,
    _sess_expanded = expanded,
    finder = finder,
    refresh = function(self, next_finder, opts)
        assert(opts.reset_prompt == false)
        refreshes = refreshes + 1
        self.finder = next_finder
    end,
}
local stop = require("sess.ui.active_refresh").start(picker, generate, rows)
assert(stop)

vim.api.nvim_chan_send(channel, "\27[2J\27[HWorking...")
assert(vim.wait(2000, function()
    return picker.finder.results[2].display:find("[working]", 1, true) ~= nil
end, 10), "picker did not refresh after terminal output")
local before = refreshes
vim.wait(600, function() return false end, 10)
assert(refreshes == before, "unchanged rows must not redraw")

vim.api.nvim_chan_send(channel, "\27[2J\27[HReady")
assert(vim.wait(2000, function()
    return picker.finder.results[2].display:find("[idle]", 1, true) ~= nil
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
