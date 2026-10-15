fixture.setup()

local api = require("sess.api")
local _, _, session = api.session.create(fixture.directory("project"))
assert(api.session.load(session.id))

local terminal = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, terminal)
local channel = vim.api.nvim_open_term(terminal, {})
vim.b[terminal].terminal_job_id = 99

local original_job_info = vim.fn.job_info
vim.fn.job_info = function()
    return { status = "run", cmd = { "codex" } }
end

vim.api.nvim_chan_send(channel, "❯ Action Required\r\nAllow command? [y/n]")
assert(vim.wait(1000, function()
    local ok, _, agents = api.agent.list(session.id)
    return ok and #agents == 1 and agents[1].status == "blocked"
end, 10))

local ok, err, explanation, diagnostics = api.agent.explain(session.id, "terminal:" .. terminal)
assert(ok, err)
assert(err == nil)
assert(type(explanation) == "table")
assert(explanation.status == "blocked")
assert(explanation.source == "screen")
assert(explanation.identity.source == "job-process-tree")
assert(explanation.manifest.id == "codex")
assert(explanation.matched_rule.id == "approval")
assert(explanation.matched_rule.priority == 100)
assert(#explanation.evidence > 0 and #explanation.evidence[1] <= 240)
assert(explanation.screen.complete == true)
assert(type(explanation.screen.line_count) == "number")
assert(type(explanation.cache) == "table")
assert(type(diagnostics) == "table")

-- The result is read-only to callers; a subsequent explanation is unchanged.
explanation.evidence[1] = string.rep("x", 1000)
explanation.identity.command = "changed"
local second_ok, second_err, second = api.agent.explain(session.id, "terminal:" .. terminal)
assert(second_ok, second_err)
assert(#second.evidence[1] <= 240)
assert(second.identity.command ~= "changed")

local registered_ok, registered_err = api.agent.register(session.id, {
    id = "integration",
    name = "codex",
    bufnr = terminal,
    status = "done",
})
assert(registered_ok, registered_err)
local integration_ok, integration_err, integration, integration_diagnostics = api.agent.explain(session.id, "integration")
assert(integration_ok, integration_err)
assert(integration.status == "done")
assert(integration.source == "integration")
assert(type(integration_diagnostics) == "table")

-- An explicit terminal status loses authority as soon as its job exits, even
-- though the terminal buffer itself remains valid.
vim.fn.job_info = function()
    return { status = "dead", cmd = { "codex" } }
end
local exited_ok, exited_err, exited_agents, exited_diagnostics = api.agent.list(session.id)
assert(exited_ok, exited_err)
assert(exited_agents[1].status == "unknown", vim.inspect(exited_agents))
assert(exited_agents[1].diagnostics and exited_agents[1].diagnostics[1]:find("job is no longer running", 1, true))
assert(#exited_diagnostics > 0)
local exited_explain_ok, exited_explain_err, exited_explanation = api.agent.explain(session.id, "integration")
assert(exited_explain_ok, exited_explain_err)
assert(exited_explanation.status == "unknown")
assert(exited_explanation.source == "unknown")
vim.fn.job_info = function()
    return { status = "run", cmd = { "codex" } }
end

-- Explain must not poison the screen cache with the integration result.
assert(api.agent.unregister(session.id, "integration"))
local unchanged_ok, unchanged_err, unchanged = api.agent.list(session.id)
assert(unchanged_ok, unchanged_err)
assert(unchanged[1].status == "blocked", vim.inspect(unchanged))

-- Registered fallback rows retain structured discovery diagnostics.
local detector = require("sess.agent.detect")
local original_explain = detector.explain
detector.explain = function()
    return {
        observation = { state = "working" },
        diagnostics = { "injected discovery diagnostic" },
    }
end
local fallback_registered, fallback_register_err = api.agent.register(session.id, {
    id = "fallback",
    name = "codex",
    bufnr = terminal,
})
assert(fallback_registered, fallback_register_err)
local fallback_ok, fallback_err, fallback_agents, fallback_diagnostics = api.agent.list(session.id)
assert(fallback_ok, fallback_err)
assert(#fallback_diagnostics > 0)
assert(fallback_diagnostics[1] == "injected discovery diagnostic")
local fallback_agent
for _, candidate in ipairs(fallback_agents) do
    if candidate.id == "fallback" then fallback_agent = candidate break end
end
assert(fallback_agent and fallback_agent.status == "working", vim.inspect(fallback_agents))
assert(fallback_agent.diagnostics and fallback_agent.diagnostics[1] == "injected discovery diagnostic")
detector.explain = original_explain
assert(api.agent.unregister(session.id, "fallback"))

-- Explicit integration status is authoritative for every valid buffer, not
-- only terminal buffers. Explanations must not attempt screen probing there.
local plain = vim.api.nvim_create_buf(false, true)
local plain_registered, plain_register_err = api.agent.register(session.id, {
    id = "plain",
    name = "codex",
    bufnr = plain,
    status = "done",
})
assert(plain_registered, plain_register_err)
local plain_ok, plain_err, plain_agents = api.agent.list(session.id)
assert(plain_ok, plain_err)
local plain_agent
for _, candidate in ipairs(plain_agents) do
    if candidate.id == "plain" then plain_agent = candidate break end
end
assert(plain_agent and plain_agent.status == "done", vim.inspect(plain_agents))
local plain_explain_ok, plain_explain_err, plain_explanation = api.agent.explain(session.id, "plain")
assert(plain_explain_ok, plain_explain_err)
assert(plain_explanation.status == "done")
assert(plain_explanation.source == "integration")
assert(api.agent.unregister(session.id, "plain"))
vim.api.nvim_buf_delete(plain, { force = true })

-- A deleted terminal cannot keep an explicit status authoritative.
local registered_again, registered_again_err = api.agent.register(session.id, {
    id = "integration",
    name = "codex",
    bufnr = terminal,
    status = "done",
})
assert(registered_again, registered_again_err)
vim.api.nvim_buf_delete(terminal, { force = true })
local deleted_ok, deleted_err, deleted = api.agent.list(session.id)
assert(deleted_ok, deleted_err)
assert(deleted[1].status == "unknown", vim.inspect(deleted))
assert(deleted[1].diagnostics and #deleted[1].diagnostics > 0, vim.inspect(deleted))
local active_ok, active_err, active_agents, _, active_diagnostics = api.agent.snapshot_active(session.id)
assert(active_ok, active_err)
assert(active_agents[1].status == "unknown")
assert(#active_diagnostics > 0)
assert(api.agent.unregister(session.id, "integration"))

-- A deleted registered target without an explicit status is always unknown and
-- reports why its previous target can no longer be observed.
local no_status_target = vim.api.nvim_create_buf(false, true)
local no_status_registered, no_status_register_err = api.agent.register(session.id, {
    id = "no-status",
    name = "codex",
    bufnr = no_status_target,
})
assert(no_status_registered, no_status_register_err)
vim.api.nvim_buf_delete(no_status_target, { force = true })
local no_status_ok, no_status_err, no_status_agents = api.agent.list(session.id)
assert(no_status_ok, no_status_err)
local no_status_agent
for _, candidate in ipairs(no_status_agents) do
    if candidate.id == "no-status" then no_status_agent = candidate break end
end
assert(no_status_agent and no_status_agent.status == "unknown", vim.inspect(no_status_agents))
assert(no_status_agent.diagnostics and #no_status_agent.diagnostics > 0, vim.inspect(no_status_agents))
assert(api.agent.unregister(session.id, "no-status"))

local missing_ok, missing_err, missing_result, missing_diagnostics = api.agent.explain(session.id, "missing")
assert(not missing_ok)
assert(missing_result == nil)
assert(type(missing_err) == "string")
assert(type(missing_diagnostics) == "table")

vim.fn.job_info = original_job_info
