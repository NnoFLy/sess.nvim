fixture.setup()

local api = require("sess.api")
local detector = require("sess.agent.detect")
local _, _, session = api.session.create(fixture.directory("project"))

local terminal = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, terminal)
vim.api.nvim_open_term(terminal, {})
vim.b[terminal].terminal_job_id = 77

assert(detector.identify("/opt/bin/codex-cli") == "codex")
assert(detector.identify("/opt/bin/opencode-cli") == "opencode")

local original_jobpid = vim.fn.jobpid
local original_readfile = vim.fn.readfile
local files = {
    ["/proc/1001/cmdline"] = { "/usr/bin/env\0AGENT=1\0/opt/bin/codex-cli\0" },
    ["/proc/1001/task/1001/children"] = {},
}
vim.fn.jobpid = function()
    return 1001
end
vim.fn.readfile = function(path, mode)
    if files[path] then
        return files[path]
    end
    return original_readfile(path, mode)
end

local ok, err, agents = api.agent.list(session.id)
assert(ok, err)
assert(#agents == 1 and agents[1].name == "codex", vim.inspect(agents))

-- A shell process can outlive the agent command while the agent remains its
-- child. Discovery must inspect the process tree rather than only argv[0].
files["/proc/1001/cmdline"] = { "/bin/sh\0-c\0wait\0" }
files["/proc/1001/task/1001/children"] = { "1002" }
files["/proc/1002/cmdline"] = { "/usr/sbin/opencode\0" }
files["/proc/1002/task/1002/children"] = {}

ok, err, agents = api.agent.list(session.id)
assert(ok, err)
assert(#agents == 1 and agents[1].name == "opencode", vim.inspect(agents))

vim.fn.jobpid = original_jobpid
vim.fn.readfile = original_readfile

-- Discovery consumes structured snapshots, retains the last usable status on a
-- failed probe, and invalidates it when the terminal job is replaced.
local discovery = require("sess.agent.discovery")
local tick, job, failed = 1, 201, false
local mock_terminal = {
    job_id = function() return job end,
    name = function() return "codex" end,
    changedtick = function() return tick end,
    snapshot = function()
        if failed then
            return { complete = false, changedtick = tick, error = "read failed" }
        end
        local lines = job == 202 and { "❯" } or { "working..." }
        return {
            complete = true,
            changedtick = tick,
            bottom_lines = lines,
            recent_lines = lines,
            current_prompt_lines = job == 202 and { "❯" } or {},
        }
    end,
}
local mock_process = {
    identify = detector.identify,
    job_agent = function() return "codex" end,
    command_agent = function() return nil end,
}
local discovered = discovery.new({ process = mock_process, terminal = mock_terminal })
local rows = discovered:list(session.id, { cache = true })
assert(#rows == 1 and rows[1].status == "working", vim.inspect(rows))
failed, tick = true, 2
rows = discovered:list(session.id, { cache = true })
assert(rows[1].status == "working", vim.inspect(rows))
assert(rows[1].diagnostics and #rows[1].diagnostics > 0, vim.inspect(rows))
failed, job, tick = false, 202, 3
rows = discovered:list(session.id, { cache = true })
assert(rows[1].status == "idle", vim.inspect(rows))
failed, tick = true, 4
rows = discovered:list(session.id, { integration = { status = "done" } })
assert(rows[1].status == "done", vim.inspect(rows))
assert(rows[1].diagnostics and #rows[1].diagnostics > 0, vim.inspect(rows))

-- Integration observations are never written into the screen cache.
failed, job, tick = false, 201, 5
rows = discovered:list(session.id, { cache = true })
assert(rows[1].status == "working", vim.inspect(rows))
rows = discovered:list(session.id, { integration = { status = "done" } })
assert(rows[1].status == "done", vim.inspect(rows))
rows = discovered:list(session.id, { cache = true })
assert(rows[1].status == "working", vim.inspect(rows))

-- A fresh integration result is call-local authority, not the last-good
-- screen result. A later failed probe therefore retains screen state rather
-- than exposing the integration result as stale screen data.
failed, tick = true, 6
rows = discovered:list(session.id, { integration = { status = "done" } })
assert(rows[1].status == "done", vim.inspect(rows))
rows = discovered:list(session.id)
assert(rows[1].status == "working", vim.inspect(rows))
assert(rows[1].diagnostics and #rows[1].diagnostics > 0, vim.inspect(rows))
local failed_explanation = assert(discovered.explain(terminal, "codex"))
assert(failed_explanation.observation.state == "working")
assert(failed_explanation.observation.source == "stale")

-- A transcript rule marked skip_state_update retains the prior valid state.
local skip = false
local skip_discovery = discovery.new({
    process = mock_process,
    terminal = mock_terminal,
    status = {
        observe = function()
            if skip then
                return { state = "working", source = "screen", skip_state_update = true, diagnostics = {} }
            end
            return { state = "idle", source = "screen", skip_state_update = false, diagnostics = {} }
        end,
    },
})
failed, tick = false, 6
rows = skip_discovery:list(session.id, { cache = true })
assert(rows[1].status == "idle", vim.inspect(rows))
rows = skip_discovery:list(session.id, { integration = { status = "done" } })
assert(rows[1].status == "done", vim.inspect(rows))
skip, tick = true, 7
rows = skip_discovery:list(session.id, { cache = true })
assert(rows[1].status == "idle", vim.inspect(rows))
assert(rows[1].diagnostics and #rows[1].diagnostics > 0, vim.inspect(rows))

-- Malformed structured snapshots become unknown diagnostics, not exceptions.
local malformed_discovery = discovery.new({
    process = mock_process,
    terminal = {
        job_id = mock_terminal.job_id,
        name = mock_terminal.name,
        changedtick = function() return 1 end,
        snapshot = function()
            return { complete = true, bottom_lines = "not a list", current_prompt_lines = {} }
        end,
    },
})
rows = malformed_discovery:list(session.id)
assert(rows[1].status == "unknown", vim.inspect(rows))
assert(rows[1].diagnostics and #rows[1].diagnostics > 0, vim.inspect(rows))
local malformed_status_discovery = discovery.new({
    process = mock_process,
    terminal = mock_terminal,
    status = {
        observe = function()
            return { state = "unknown", source = {}, diagnostics = { "bad" } }
        end,
    },
})
rows = malformed_status_discovery:list(session.id)
assert(rows[1].status == "unknown", vim.inspect(rows))
assert(rows[1].diagnostics and #rows[1].diagnostics > 0, vim.inspect(rows))
local malformed_line_discovery = discovery.new({
    process = mock_process,
    terminal = {
        job_id = mock_terminal.job_id,
        name = mock_terminal.name,
        changedtick = function() return 1 end,
        snapshot = function()
            return { complete = true, bottom_lines = { "safe", 42 }, current_prompt_lines = {} }
        end,
    },
})
rows = malformed_line_discovery:list(session.id)
assert(rows[1].status == "unknown", vim.inspect(rows))
assert(rows[1].diagnostics and #rows[1].diagnostics > 0, vim.inspect(rows))

-- Every structured snapshot field is validated before discovery or explain
-- performs length/index operations on it.
for field, value in pairs({
    recent_lines = "not a list",
    current_prompt_lines = "not a list",
    before_current_prompt_lines = "not a list",
    top_lines = "not a list",
    bufnr = "not a buffer",
    changedtick = "not a tick",
    osc_title = {},
    complete = "not a boolean",
    error = {},
}) do
    local malformed_snapshot = discovery.new({
        process = mock_process,
        terminal = {
            job_id = mock_terminal.job_id,
            name = mock_terminal.name,
            changedtick = function() return 1 end,
            snapshot = function()
                return { [field] = value, complete = field == "complete" and value or true }
            end,
        },
    })
    local listed, list_error = pcall(function() return malformed_snapshot:list(session.id) end)
    assert(listed, field .. " raised: " .. tostring(list_error))
    rows = malformed_snapshot:list(session.id)
    assert(rows[1].status == "unknown", field .. ": " .. vim.inspect(rows))
    assert(rows[1].diagnostics and #rows[1].diagnostics > 0, field .. ": " .. vim.inspect(rows))
end
local malformed_explain = discovery.new({
    process = mock_process,
    terminal = {
        job_id = mock_terminal.job_id,
        name = mock_terminal.name,
        changedtick = function() return 1 end,
        snapshot = function()
            return { complete = true, recent_lines = "not a list" }
        end,
    },
})
local explained, explanation_or_error = pcall(function()
    return malformed_explain.explain(terminal, "codex")
end)
assert(explained, tostring(explanation_or_error))
assert(explanation_or_error.screen.line_count == 0)
assert(#explanation_or_error.diagnostics > 0)

local process_probe = require("sess.agent.process_probe")
assert(process_probe.command_agent({ "sh", "-c", "echo codex" }) == nil)
assert(process_probe.command_agent({ "env", "CODEX=codex" }) == nil)
assert(process_probe.command_agent({ "env", "CODEX=codex", "codex" }) == "codex")
assert(process_probe.command_agent({ "python", "-c", "codex" }) == nil)
-- Runtime option values are not executable positions. Only the script or
-- command position may identify an agent.
assert(process_probe.command_agent({ "python", "-m", "codex" }) == nil)
assert(process_probe.command_agent({ "node", "--require", "codex" }) == nil)
assert(process_probe.command_agent({ "node", "--require=codex" }) == nil)
assert(process_probe.command_agent({ "node", "--require=fixture", "codex" }) == "codex")
assert(process_probe.command_agent({ "node", "--require", "fixture", "codex" }) == "codex")
assert(process_probe.command_agent({ "npx", "--package", "codex", "echo" }) == nil)
assert(process_probe.command_agent({ "npm", "--prefix", "codex", "run", "build" }) == nil)
assert(process_probe.command_agent({ "npx", "--package", "fixture", "codex" }) == "codex")
assert(process_probe.command_agent({ "env", "-u", "CODEX", "codex" }) == "codex")
local huge_argv = {}
for index = 1, 65 do huge_argv[index] = "arg" end
local huge_agent, huge_diagnostic = process_probe.command_agent(huge_argv)
assert(huge_agent == nil)
assert(huge_diagnostic and huge_diagnostic:find("truncated", 1, true))
local long_agent, long_diagnostic = process_probe.command_agent({ string.rep("x", 4097) })
assert(long_agent == nil)
assert(long_diagnostic and long_diagnostic:find("too long", 1, true))
-- nvim_get_proc() does not include argv on all supported versions. The
-- process probe must supplement it from /proc so a node wrapper can still
-- reveal the agent command.
local original_get_proc = vim.api.nvim_get_proc
local original_get_proc_children = vim.api.nvim_get_proc_children
vim.api.nvim_get_proc = function()
    return { name = "node", pid = 1 }
end
vim.api.nvim_get_proc_children = function() return {} end
local current_readfile = vim.fn.readfile
vim.fn.readfile = function(path, mode)
    if files[path] then return files[path] end
    return original_readfile(path, mode)
end
files["/proc/1/cmdline"] = { "/usr/bin/node\0/opt/bin/codex-cli\0" }
assert(process_probe.tree_agent(1) == "codex")
vim.fn.readfile = current_readfile
vim.api.nvim_get_proc = original_get_proc
vim.api.nvim_get_proc_children = original_get_proc_children

local original_process, original_children = process_probe.process, process_probe.children
local visited = 0
process_probe.process = function()
    visited = visited + 1
    return { name = "sh" }
end
process_probe.children = function(pid)
    return { pid * 2, pid * 2 + 1 }
end
assert(process_probe.tree_agent(1) == nil)
assert(visited == 256, "process traversal bound was not applied")
process_probe.process, process_probe.children = original_process, original_children

local original_get_children = vim.api.nvim_get_proc_children
vim.api.nvim_get_proc_children = function()
    local children = {}
    for index = 1, 257 do children[index] = index end
    return children
end
local bounded_children, children_diagnostic = process_probe.children(1)
assert(#bounded_children == 0)
assert(children_diagnostic and children_diagnostic:find("truncated", 1, true))
vim.api.nvim_get_proc_children = function() return { "malformed" } end
local malformed_children, malformed_diagnostic = process_probe.children(1)
assert(#malformed_children == 0)
assert(malformed_diagnostic and malformed_diagnostic:find("malformed", 1, true))
vim.api.nvim_get_proc_children = original_get_children

-- A failed unknown result is not cacheable: recovery is retried even when the
-- terminal changedtick has not moved.
local retry_failed = true
local retry_terminal = {
    job_id = function() return 303 end,
    name = function() return "codex" end,
    changedtick = function() return 17 end,
    snapshot = function()
        if retry_failed then return { complete = false, changedtick = 17, error = "temporary" } end
        return {
            complete = true,
            changedtick = 17,
            bottom_lines = { "working..." },
            recent_lines = { "working..." },
            current_prompt_lines = {},
        }
    end,
}
local retry_discovery = discovery.new({ process = mock_process, terminal = retry_terminal })
rows = retry_discovery:list(session.id, { cache = true })
assert(rows[1].status == "unknown", vim.inspect(rows))
retry_failed = false
rows = retry_discovery:list(session.id, { cache = true })
assert(rows[1].status == "working", vim.inspect(rows))

-- A temporary identity-probe failure retains the known live agent row and
-- exposes the failure instead of silently making the agent disappear.
local identity_failed = false
local flaky_identity = discovery.new({
    process = {
        identify = detector.identify,
        job_agent = function()
            if identity_failed then error("temporary identity failure") end
            return "codex"
        end,
        command_agent = function() return nil end,
    },
    terminal = {
        job_id = function() return 404 end,
        name = function() return nil end,
        changedtick = function() return 1 end,
        snapshot = function()
            return {
                complete = true,
                changedtick = 1,
                bottom_lines = { "working..." },
                recent_lines = { "working..." },
                current_prompt_lines = {},
            }
        end,
    },
})
rows = flaky_identity:list(session.id)
assert(#rows == 1 and rows[1].name == "codex", vim.inspect(rows))
identity_failed = true
rows = flaky_identity:list(session.id)
assert(#rows == 1 and rows[1].name == "codex", vim.inspect(rows))
assert(rows[1].probe_failed)
assert(rows[1].diagnostics and rows[1].diagnostics[1]:find("identity probe failed", 1, true))
