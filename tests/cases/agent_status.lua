fixture.setup()

local api = require("sess.api")
local _, _, session = api.session.create(fixture.directory("project"))

vim.o.lines = 80
local terminal = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, terminal)
local channel = vim.api.nvim_open_term(terminal, {})
vim.b[terminal].terminal_job_id = 99

local original_job_info = vim.fn.job_info
local name = "codex"
vim.fn.job_info = function()
    return { status = "run", cmd = { name } }
end

local function current_status()
    local ok, err, agents = api.agent.list(session.id)
    assert(ok, err)
    assert(#agents == 1, vim.inspect(agents))
    return agents[1].status
end

local function render(text, expected)
    -- Exercise the terminal emulator, including ANSI clears and blank screen
    -- padding, rather than replacing buffer text by hand.
    vim.api.nvim_chan_send(channel, "\27[2J\27[H" .. text)
    assert(vim.wait(1000, function()
        return current_status() == expected
    end, 10), "expected " .. expected .. ", got " .. tostring(current_status()))
end

render("• Working (2s) · esc to interrupt", "working")
local agent_id = "terminal:" .. terminal
assert(api.agent.focus(session.id, agent_id))
assert(next(require("sess.state").get_agents(session.id)) == nil)
render("Action Required\r\nAllow command? [y/n]", "blocked")
render("› ", "idle")
render("Unrecognised screen", "unknown")

-- Registration and focus must not turn inferred status into an override.
assert(api.agent.register(nil, { id = "registered", name = name, bufnr = terminal }))
render("Working...", "working")
assert(api.agent.focus(nil, "registered"))
render("› ", "idle")
assert(api.agent.update(nil, "registered", { status = "done" }))
render("Working...", "done")
assert(api.agent.unregister(nil, "registered"))

name = "pi"
render("── ⠋ Working ─────────────", "working")
render("Ready for your next prompt", "idle")
vim.fn.job_info = original_job_info
