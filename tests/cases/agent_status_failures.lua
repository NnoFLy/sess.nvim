fixture.setup()

local status = require("sess.agent.status")
local discovery = require("sess.agent.discovery")
local process = require("sess.agent.process_probe")
local terminal = require("sess.agent.terminal_probe")

local function no_throw(name, run)
    local ok, result = pcall(run)
    assert(ok, name .. " threw: " .. tostring(result))
    return result
end

local function unknown(observation, text)
    assert(observation.state == "unknown", text .. ": " .. vim.inspect(observation))
    assert(#(observation.diagnostics or {}) > 0, text .. " omitted diagnostics")
end

-- Malformed manifests and screen records are untrusted data: each is skipped
-- or reported as an unknown observation, never raised through the API.
local malformed_manifests = {
    { "not a table", "not a manifest" },
    { "missing version", { default = "unknown", rules = {} } },
    { "fractional version", { version = 1.5, default = "unknown", rules = {} } },
    { "bad default", { version = 1, default = {}, rules = {} } },
    { "missing rules", { version = 1, default = "unknown" } },
    { "unknown rule field", { version = 1, default = "unknown", rules = { { id = "x", state = "idle", priority = 1, region = "recent", contains = "x", extra = true } } } },
    { "bad rule id", { version = 1, default = "unknown", rules = { { id = {}, state = "idle", priority = 1, region = "recent", contains = "x" } } } },
    { "bad state", { version = 1, default = "unknown", rules = { { id = "x", state = {}, priority = 1, region = "recent", contains = "x" } } } },
    { "bad priority", { version = 1, default = "unknown", rules = { { id = "x", state = "idle", priority = "1", region = "recent", contains = "x" } } } },
    { "bad region", { version = 1, default = "unknown", rules = { { id = "x", state = "idle", priority = 1, region = "whole", contains = "x" } } } },
    { "empty matcher", { version = 1, default = "unknown", rules = { { id = "x", state = "idle", priority = 1, region = "recent" } } } },
    { "multiple operators", { version = 1, default = "unknown", rules = { { id = "x", state = "idle", priority = 1, region = "recent", contains = "x", regex = "x" } } } },
    { "empty contains", { version = 1, default = "unknown", rules = { { id = "x", state = "idle", priority = 1, region = "recent", contains = "" } } } },
    { "bad regex", { version = 1, default = "unknown", rules = { { id = "x", state = "idle", priority = 1, region = "recent", regex = "[" } } } },
    { "bad contains_any", { version = 1, default = "unknown", rules = { { id = "x", state = "idle", priority = 1, region = "recent", contains_any = { [2] = "x" } } } } },
    { "bad nested matcher", { version = 1, default = "unknown", rules = { { id = "x", state = "idle", priority = 1, region = "recent", any = { { contains = 3 } } } } } },
    { "too deep", (function()
        local matcher = { contains = "x" }
        for _ = 1, 20 do matcher = { any = { matcher } } end
        return { version = 1, default = "unknown", rules = { { id = "x", state = "idle", priority = 1, region = "recent", any = { matcher } } } }
    end)() },
    { "too many rules", (function()
        local rules = {}
        for index = 1, 130 do rules[index] = { id = "r" .. index, state = "idle", priority = index, region = "recent", contains = "x" } end
        return { version = 1, default = "unknown", rules = rules }
    end)() },
}
for _, item in ipairs(malformed_manifests) do
    unknown(no_throw("manifest/" .. item[1], function()
        return status.observe({ name = "fixture", manifest = item[2], screen = { complete = true, recent_lines = { "safe" } } })
    end), "manifest/" .. item[1])
end

local malformed_screens = {
    { "missing screen", nil },
    { "missing complete", { recent_lines = { "working..." } } },
    { "screen string", "bad" },
    { "bad complete", { complete = "yes" } },
    { "incomplete", { complete = false, error = "short" } },
    { "line string", { complete = true, recent_lines = "bad" } },
    { "line number", { complete = true, recent_lines = { 42 } } },
    { "line sparse", { complete = true, recent_lines = { [2] = "x" } } },
    { "line fractional key", { complete = true, recent_lines = { [1.5] = "x" } } },
    { "line too long", { complete = true, recent_lines = { string.rep("x", 1001) } } },
    { "too many lines", (function() local lines = {}; for i = 1, 201 do lines[i] = "x" end; return { complete = true, recent_lines = lines } end)() },
    { "title table", { complete = true, osc_title = {} } },
    { "title too long", { complete = true, osc_title = string.rep("x", 1001) } },
    { "error table", { complete = true, error = {} } },
    { "error too long", { complete = true, error = string.rep("x", 1001) } },
}
for _, item in ipairs(malformed_screens) do
    unknown(no_throw("screen/" .. item[1], function()
        return status.observe({ name = "codex", screen = item[2] })
    end), "screen/" .. item[1])
end

-- Every limit is bounded, including evidence, matcher values, and aggregate
-- snapshot bytes. A valid result must not expose arbitrary probe text.
local oversized_rule = {
    version = 1, default = "unknown", rules = {
        { id = "x", state = "idle", priority = 1, region = "recent", contains = string.rep("x", 257) },
    },
}
unknown(status.observe({ name = "fixture", manifest = oversized_rule, screen = { complete = true, recent_lines = { "x" } } }), "pattern bytes")
local oversized_screen = { complete = true, recent_lines = {} }
for index = 1, 200 do oversized_screen.recent_lines[index] = string.rep("x", 330) end
unknown(status.observe({ name = "codex", screen = oversized_screen }), "total screen bytes")

-- Arbitrary values from injected discovery probes must not throw, and a bad
-- observation must be a diagnostic rather than a cacheable status.
local api = require("sess.api")
local _, _, session = api.session.create(fixture.directory("project"))
assert(api.session.load(session.id))
local probe_buffer = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, probe_buffer)
vim.api.nvim_open_term(probe_buffer, {})
vim.b[probe_buffer].terminal_job_id = 700
local function malformed_discovery(snapshot)
    local agent = discovery.new({
        process = {
            identify = function(value) return value end,
            job_agent = function() return "codex" end,
            command_agent = function() return nil end,
        },
        terminal = {
            job_id = function() return 700 end,
            name = function() return "codex" end,
            job_alive = function() return true end,
            changedtick = function() return 1 end,
            snapshot = function() return snapshot end,
        },
    })
    local rows = no_throw("discovery malformed snapshot", function() return agent:list(session.id) end)
    assert(rows[1].status == "unknown" and rows[1].probe_failed)
    assert(#(rows[1].diagnostics or {}) > 0)
end
for _, snapshot in ipairs({
    nil, false, "text", { recent_lines = { "working..." } }, { complete = true, recent_lines = { 1 } },
    { complete = true, recent_lines = { [0] = "bad" } },
    { complete = true, recent_lines = { string.rep("x", 1001) } },
    { complete = true, recent_lines = (function() local lines = {}; for i = 1, 201 do lines[i] = "x" end; return lines end)() },
}) do malformed_discovery(snapshot) end

for _, observation in ipairs({
    { state = "working", source = "screen", evidence = (function() local x = {}; for i = 1, 33 do x[i] = "x" end; return x end)() },
    { state = "working", source = "screen", evidence = { string.rep("x", 241) } },
    { state = "working", source = "screen", diagnostics = (function() local x = {}; for i = 1, 65 do x[i] = "x" end; return x end)() },
    { state = string.rep("x", 241), source = "screen" },
}) do
    local malformed = discovery.new({
        process = {
            identify = function(value) return value end,
            job_agent = function() return "codex" end,
            command_agent = function() return nil end,
        },
        terminal = {
            job_id = function() return 701 end,
            name = function() return "codex" end,
            job_alive = function() return true end,
            changedtick = function() return 1 end,
            snapshot = function() return { complete = true, recent_lines = { "safe" } } end,
        },
        status = { observe = function() return observation end },
    })
    local rows = no_throw("observation bounds", function() return malformed:list(session.id) end)
    assert(rows[1].status == "unknown" and #(rows[1].diagnostics or {}) > 0)
end

-- Arbitrary bounded control characters are sanitized rather than interpreted
-- as matcher syntax or allowed into unbounded evidence.
for byte = 0, 255 do
    local value = string.char(byte) .. "safe"
    local result = no_throw("control byte " .. byte, function()
        return status.observe({ name = "codex", screen = { complete = true, recent_lines = { value } } })
    end)
    assert(type(result.state) == "string" and #(result.diagnostics or {}) <= 64)
end

-- Invalid process argv and PID/child data are diagnosed, not executed or
-- allowed to escape the bounded traversal.
for _, argv in ipairs({
    {}, { [2] = "codex" }, { "codex", [3] = "x" }, { "codex", 42 },
    { string.rep("x", 4097) }, (function() local x = {}; for i = 1, 65 do x[i] = "x" end; return x end)(),
    42, {},
}) do
    no_throw("argv malformed", function()
        local agent, diagnostic = process.command_agent(argv)
        assert(agent == nil)
        if type(argv) == "table" and (#argv > 0 or next(argv) ~= nil) then assert(diagnostic) end
    end)
end
for _, pid in ipairs({ false, 0, -1, 1.5, "1", {} }) do
    no_throw("pid malformed", function()
        local children, diagnostic = process.children(pid)
        assert(type(children) == "table" and #children == 0 and diagnostic)
    end)
end
no_throw("nil pid malformed", function()
    local children, diagnostic = process.children(nil)
    assert(type(children) == "table" and #children == 0 and diagnostic)
end)

local old_children = vim.api.nvim_get_proc_children
local old_get_proc = vim.api.nvim_get_proc
vim.api.nvim_get_proc_children = function() return { 0 } end
local children, children_error = process.children(1)
assert(#children == 0 and children_error and children_error:find("malformed", 1, true))
vim.api.nvim_get_proc_children = function() return { [1] = 1, [3] = 1 } end
children, children_error = process.children(1)
assert(#children == 0 and children_error and children_error:find("malformed", 1, true))
vim.api.nvim_get_proc_children = old_children
local old_process, old_tree_children = process.process, process.children
process.process = function() return nil, "process record inaccessible" end
process.children = function() return {}, "process children inaccessible" end
no_throw("inaccessible process", function()
    local agent, diagnostic = process.tree_agent(1)
    assert(agent == nil and diagnostic)
end)
process.process, process.children = old_process, old_tree_children
vim.api.nvim_get_proc = old_get_proc

-- Terminal normalization is also failure-safe for a broken buffer read.
local old_line_count, old_get_lines = vim.api.nvim_buf_line_count, vim.api.nvim_buf_get_lines
vim.api.nvim_buf_line_count = function() error("line count unavailable") end
local failed_snapshot = no_throw("terminal line count", function() return terminal.snapshot(1) end)
assert(not failed_snapshot.complete and failed_snapshot.error)
vim.api.nvim_buf_line_count, vim.api.nvim_buf_get_lines = old_line_count, old_get_lines

print("agent_status_failures: malformed probe corpus passed")
