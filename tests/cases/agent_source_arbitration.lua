fixture.setup()

local api = require("sess.api")
local detector = require("sess.agent.discovery")
local status = require("sess.agent.status")
local _, _, session = api.session.create(fixture.directory("project"))
assert(api.session.load(session.id))

local terminal = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, terminal)
vim.api.nvim_open_term(terminal, {})
vim.b[terminal].terminal_job_id = 902
local screen = { current = { "❯" }, bottom = { "❯" }, tick = 1 }
local probes = {
    process = {
        job_agent = function() return "codex" end,
        command_agent = function() return nil end,
        identify = function(value) return value end,
    },
    terminal = {
        job_id = function() return 902 end,
        name = function() return "codex" end,
        job_alive = function() return true end,
        changedtick = function() return screen.tick end,
        snapshot = function()
            return {
                bufnr = terminal,
                changedtick = screen.tick,
                complete = true,
                recent_lines = screen.bottom,
                bottom_lines = screen.bottom,
                current_prompt_lines = screen.current,
            }
        end,
    },
    status = status,
}
local discovered = detector.new(probes)
local rows = discovered:list(session.id)
assert(#rows == 1 and rows[1].status == "idle" and rows[1].source == "screen", vim.inspect(rows))

rows = discovered:list(session.id, { integration = { source = "worker", seq = 1, status = "working" } })
assert(rows[1].status == "working" and rows[1].source == "integration", vim.inspect(rows))
rows = discovered:list(session.id, { integration = { source = "worker", seq = 2, status = "done" } })
assert(rows[1].status == "done" and rows[1].source == "integration", vim.inspect(rows))

-- A current, high-confidence blocker is safer than a non-blocking lifecycle
-- report, while a blocked lifecycle report remains authoritative.
screen.current = { "Action Required: Allow command? [y/n]" }
screen.bottom = screen.current
screen.tick = 2
rows = discovered:list(session.id, { integration = { source = "worker", seq = 3, status = "done" } })
assert(rows[1].status == "blocked" and rows[1].source == "screen", vim.inspect(rows))
rows = discovered:list(session.id, { integration = { source = "worker", seq = 4, status = "blocked" } })
assert(rows[1].status == "blocked" and rows[1].source == "integration", vim.inspect(rows))

-- An expired/released integration is not an authority. A complete unmatched
-- snapshot is a fresh unknown/fallback result, not retained working state.
screen.current = {}
screen.bottom = { "unrecognized output" }
screen.tick = 3
rows = discovered:list(session.id, { integration = {
    status = "working",
    expires_at = 0,
} })
assert(rows[1].status == "unknown" and rows[1].source == "fallback", vim.inspect(rows))
assert(rows[1].authority == "derived", vim.inspect(rows))
rows = discovered:list(session.id, { integration = {
    status = "working",
    released = true,
} })
assert(rows[1].status == "unknown" and rows[1].source == "fallback", vim.inspect(rows))

local explanation = assert(discovered.explain(terminal, "codex", {
    integration = { source = "worker", seq = 5, status = "working" },
}))
assert(explanation.observation.source == "integration")
assert(explanation.observation.state == "working")
assert(explanation.observation.authority == "lifecycle")
assert(explanation.screen.complete == true)
assert(explanation.cache.status == false)

-- The injected discovery path never starts or stops a process.
assert(type(probes.terminal.job_alive) == "function")
