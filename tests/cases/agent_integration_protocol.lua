fixture.setup()

local api = require("sess.api")
local runtime_state = require("sess.state")
local _, _, session = api.session.create(fixture.directory("project"))
assert(api.session.load(session.id))

local terminal = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, terminal)
vim.api.nvim_open_term(terminal, {})
vim.b[terminal].terminal_job_id = 901
local original_job_info = vim.fn.job_info
vim.fn.job_info = function() return { status = "run", cmd = { "codex" } } end

local registered, register_err = api.agent.register(session.id, {
    id = "protocol",
    name = "codex",
    bufnr = terminal,
})
assert(registered, register_err)

local ok, err, accepted = api.agent.report(session.id, "protocol", {
    source = "fixture",
    seq = 1,
    status = "working",
    info = "editing",
})
assert(ok, err)
assert(accepted.status == "working" and accepted.integration.seq == 1)
accepted.integration.info = string.rep("x", 1000)
local listed_ok, listed_err, listed = api.agent.list(session.id)
assert(listed_ok, listed_err)
assert(listed[1].status == "working" and listed[1].source == "integration")
assert(listed[1].info == "editing")

local duplicate_ok, duplicate_err = api.agent.report(session.id, "protocol", {
    source = "fixture",
    seq = 1,
    status = "done",
})
assert(not duplicate_ok and duplicate_err:find("stale", 1, true))
local old_ok = api.agent.report(session.id, "protocol", {
    source = "fixture",
    seq = 0,
    status = "idle",
})
assert(not old_ok)
local unchanged_ok, unchanged_err, unchanged = api.agent.list(session.id)
assert(unchanged_ok, unchanged_err)
assert(unchanged[1].status == "working" and unchanged[1].info == "editing")

local second_ok, second_err = api.agent.report(session.id, "protocol", {
    source = "fixture",
    seq = 2,
    status = "done",
})
assert(second_ok, second_err)
local other_ok, other_err = api.agent.report(session.id, "protocol", {
    source = "other",
    seq = 1,
    status = "idle",
})
assert(other_ok, other_err)
local both_ok, both_err, both = api.agent.list(session.id)
assert(both_ok, both_err)
assert(both[1].status == "idle" and both[1].source == "integration")

for _, malformed in ipairs({
    { source = "", seq = 3, status = "idle" },
    { source = string.rep("s", 129), seq = 3, status = "idle" },
    { source = "fixture", seq = -1, status = "idle" },
    { source = "fixture", seq = 3.5, status = "idle" },
    { source = "fixture", seq = 3, status = "invalid" },
    { source = "fixture", seq = 3, status = "idle", extra = true },
    { source = "fixture", seq = 3, status = "idle", info = string.rep("i", 241) },
    { source = "fixture", seq = 3, status = "idle", ttl = 0 },
}) do
    local malformed_ok = api.agent.report(session.id, "protocol", malformed)
    assert(not malformed_ok, vim.inspect(malformed))
end

local release_ok, release_err, released = api.agent.release(session.id, "protocol", {
    source = "other",
    seq = 2,
})
assert(release_ok, release_err)
assert(released.status == "done" and released.source == "integration")
local stale_release = api.agent.release(session.id, "protocol", { source = "other", seq = 1 })
assert(not stale_release)

local explanation_ok, explanation_err, explanation = api.agent.explain(session.id, "protocol")
assert(explanation_ok, explanation_err)
assert(explanation.integration and explanation.integration.source == "fixture")
assert(explanation.integration.seq == 2 and explanation.integration.fresh)
explanation.integration.source = "mutated"
local explanation_again_ok, explanation_again_err, explanation_again = api.agent.explain(session.id, "protocol")
assert(explanation_again_ok, explanation_again_err)
assert(explanation_again.integration.source == "fixture")

-- Expiry uses the injected monotonic clock and never remains authoritative.
local clock = vim.uv.hrtime() / 1000000
api.agent._set_report_clock(function() return clock end)
assert(api.agent.release(session.id, "protocol", { source = "fixture", seq = 3 }))
assert(api.agent.report(session.id, "protocol", {
    source = "expiry", seq = 1, status = "working", ttl = 1,
}))
clock = clock + 1001
local expired_ok, expired_err, expired = api.agent.list(session.id)
assert(expired_ok, expired_err)
assert(expired[1].status ~= "working" or expired[1].source ~= "integration")
local expired_explain_ok, expired_explain_err, expired_explain = api.agent.explain(session.id, "protocol")
assert(expired_explain_ok, expired_explain_err)
assert(expired_explain.integration and not expired_explain.integration.fresh)
assert(table.concat(expired_explain.diagnostics, " "):find("expired", 1, true))
api.agent._set_report_clock()

-- A replacement job invalidates the old incarnation's authority and starts
-- sequence state afresh for the same source.
vim.b[terminal].terminal_job_id = 902
local replacement_ok, replacement_err = api.agent.report(session.id, "protocol", {
    source = "fixture", seq = 1, status = "done",
})
assert(replacement_ok, replacement_err)
local replacement_list_ok, replacement_list_err, replacement_list = api.agent.list(session.id)
assert(replacement_list_ok, replacement_list_err)
assert(replacement_list[1].status == "done" and replacement_list[1].source == "integration")
vim.b[terminal].terminal_job_id = 903
local replaced_list_ok, replaced_list_err, replaced_list = api.agent.list(session.id)
assert(replaced_list_ok, replaced_list_err)
assert(replaced_list[1].status ~= "done" or replaced_list[1].source ~= "integration")
local replaced_snapshot_ok, replaced_snapshot_err, replaced_snapshot_agents = api.agent.snapshot_active(session.id)
assert(replaced_snapshot_ok, replaced_snapshot_err)
assert(replaced_snapshot_agents[1].status == replaced_list[1].status)
local replaced_explain_ok, replaced_explain_err, replaced_explain = api.agent.explain(session.id, "protocol")
assert(replaced_explain_ok, replaced_explain_err)
assert(replaced_explain.status == replaced_list[1].status)

-- Reports are runtime-only and do not become part of the active view or the
-- persisted session snapshot.
local view = runtime_state.get_view(session.id)
assert(not (view and view.integration))
local storage = require("sess.storage")
local snapshot_path = assert(storage.get_session_path(session.id))
local snapshot = vim.fn.filereadable(snapshot_path) == 1 and table.concat(vim.fn.readfile(snapshot_path), "\n") or ""
assert(not snapshot:find("fixture", 1, true))

-- Removing and recreating an agent resets its runtime report sequence.
assert(api.agent.unregister(session.id, "protocol"))
local recreated, recreate_err = api.agent.register(session.id, {
    id = "protocol",
    name = "codex",
    bufnr = terminal,
})
assert(recreated, recreate_err)
local reset_ok, reset_err = api.agent.report(session.id, "protocol", {
    source = "fixture",
    seq = 1,
    status = "idle",
})
assert(reset_ok, reset_err)

vim.fn.job_info = original_job_info
