local status = require("sess.agent.status")
local terminal = require("sess.agent.terminal_probe")
local process = require("sess.agent.process_probe")

-- Collect failures so one bad manifest does not hide the rest of the corpus.
local failures = {}
local function check(name, run)
    local ok, err = pcall(run)
    if not ok then failures[#failures + 1] = name .. ": " .. tostring(err) end
end

local function patched(target, replacements, run)
    local originals = {}
    for key, value in pairs(replacements) do
        originals[key], target[key] = target[key], value
    end
    local ok, err = pcall(run)
    for key in pairs(replacements) do target[key] = originals[key] end
    assert(ok, err)
end

-- Exercise normalization and prompt extraction without a terminal job, sleeps,
-- or an installed agent. Buffer reads remain zero-based, end-exclusive.
local function snapshot(lines)
    local result
    patched(vim.api, {
        nvim_buf_get_changedtick = function() return 17 end,
        nvim_buf_line_count = function() return #lines end,
        nvim_buf_get_lines = function(_, first, last)
            local slice = {}
            for index = first + 1, last do slice[#slice + 1] = lines[index] end
            return slice
        end,
    }, function() result = terminal.snapshot(1) end)
    return result
end

local title_manifest = {
    id = "title-fixture",
    version = 1,
    default = "unknown",
    rules = {
        { id = "progress", state = "working", priority = 1, region = "osc_title", contains = "progress: 42%" },
    },
}

local fixtures = {}
local function screen(name, agent, region, input, state, source, rule, manifest)
    fixtures[#fixtures + 1] = {
        name = name, agent = agent, region = region, input = input,
        state = state, source = source, rule = rule or false, manifest = manifest,
    }
end

screen("Codex interrupt UI", "codex", "bottom_non_empty", { "• Working (2s) · esc to interrupt" }, "working", "screen", "working")
screen("Claude thinking UI", "claude", "bottom_non_empty", { "✳ Thinking..." }, "working", "screen", "claude-working")
screen("OpenCode thinking UI", "opencode", "bottom_non_empty", { "Thinking..." }, "working", "screen", "opencode-working")
screen("OpenCode running UI", "opencode", "bottom_non_empty", { "Running..." }, "working", "screen", "opencode-working")
screen("Pi spinner", "pi", "bottom_non_empty", { "⠋ Working" }, "working", "screen", "working")
screen("Pi banner", "pi", "bottom_non_empty", { "── Working ──" }, "working", "screen", "working")
for _, agent in ipairs({ "codex", "claude", "opencode", "pi" }) do
    local approval = agent == "claude" and "claude-approval" or agent == "opencode" and "opencode-approval" or "approval"
    local idle = agent == "claude" and "claude-idle-prompt" or agent == "opencode" and "opencode-idle-prompt" or "idle-prompt"
    local marker = agent == "opencode" and "›" or "❯"
    screen(agent .. " live approval", agent, "current_prompt", { marker .. " Allow command? [y/n]" }, "blocked", "screen", approval)
    screen(agent .. " idle prompt", agent, "current_prompt", { marker }, "idle", "screen", idle)
    screen(agent .. " colored approval", agent, "current_prompt", { "\27[31m" .. marker .. " Allow command? [y/n]\27[0m" }, "blocked", "screen", approval)
    screen(agent .. " colored idle", agent, "current_prompt", { "\27[32m" .. marker .. "\27[0m" }, "idle", "screen", idle)
    screen(agent .. " old approval then idle", agent, "current_prompt", { "Allow command? [y/n]", marker }, "idle", "screen", idle)
    screen(agent .. " blocker beats old work", agent, "current_prompt", { "Working...", marker .. " Allow command? [y/n]" }, "blocked", "screen", approval)
    local default = agent == "pi" and "idle" or "unknown"
    for _, entry in ipairs({
        { "old approval", { "Allow command? [y/n]" } },
        { "historical symbol", { "previous output contained ❯ and ›", "ordinary output" } },
        { "blank", { "", "" } },
        { "whitespace", { " ", "\t", "  " } },
        { "unrecognized UI", { "opaque agent interface v999" } },
        { "shell mention", { "$ printf '%s' " .. agent } },
        { "user working", { "The user said we are working on documentation" } },
        { "user running", { "The user said we are running out of time" } },
        { "user thinking", { "The user said we are thinking about lunch" } },
    }) do
        screen(agent .. " " .. entry[1], agent, "recent", entry[2], default, "fallback")
    end
    -- Text after a prompt marker is not evidence of working/running/thinking;
    -- conservative manifests may fall back, but must not classify it as working.
    screen(agent .. " user text at prompt", agent, "current_prompt", { marker .. " Explain working, running and thinking in this sentence" }, default, "fallback")
end
screen("unknown agent generic text", "not-an-agent", "recent", { "❯ Allow command? [y/n]", "Working..." }, "unknown", "unknown")
for _, control in ipairs({
    { "OSC BEL", "\27]0;progress: 42%\7" },
    { "OSC ST", "\27]2;progress: 42%\27\\" },
    { "C1 OSC ST", "\1572;progress: 42%\156" },
}) do
    screen(control[1] .. " custom title", "fixture", "osc_title", { control[2] .. "visible text" }, "working", "screen", "progress", title_manifest)
end
screen("C1 CSI approval", "codex", "current_prompt", { "\15531m❯ Allow command? [y/n]\1550m" }, "blocked", "screen", "approval")

for _, case in ipairs(fixtures) do
    check("screen/" .. case.name, function()
        local captured = snapshot(case.input)
        assert(captured.complete, vim.inspect(captured))
        local result = status.observe({ name = case.agent, manifest = case.manifest, screen = captured })
        assert(result.state == case.state and result.source == case.source and (result.rule_id or false) == case.rule,
            "expected " .. case.state .. "/" .. case.source .. "/" .. tostring(case.rule) .. ", got " .. vim.inspect(result))
        if case.rule then assert(result.rule_region == case.region, vim.inspect(result)) end
        assert(#result.evidence <= 3)
        for _, line in ipairs(result.evidence) do
            assert(#line <= 240 and not line:find("[%z\1-\8\11-\31\127]"), "unsanitized evidence: " .. vim.inspect(line))
        end
    end)
end

for _, case in ipairs({
    { "CSI", "\27[1;31m❯\27[0m", "❯" },
    { "OSC BEL", "\27]0;hidden\7❯", "❯" },
    { "OSC ST", "\27]2;hidden\27\\❯", "❯" },
    { "C1 CSI", "\15532m❯\1550m", "❯" },
    { "C1 OSC", "\1570;hidden\156❯", "❯" },
    { "UTF-8", "⠋ ❯ › ✳", "⠋ ❯ › ✳" },
    { "controls", "\0\1\7\8\127\128\159\r\t❯", "\t❯" },
    { "unterminated CSI", "safe\27[31", "safe" },
    { "unterminated OSC", "safe\27]0;hidden", "safe" },
    { "long line", string.rep("x", 1100), string.rep("x", 1000) },
    { "UTF-8 cut at lead", string.rep("x", 999) .. "❯", string.rep("x", 999) },
    { "UTF-8 cut in sequence", string.rep("x", 998) .. "❯", string.rep("x", 998) },
}) do
    check("normalization/" .. case[1], function()
        fixture.equal({ case[3] }, snapshot({ case[2] }).recent_lines)
    end)
end
check("normalization/read and region bounds", function()
    local lines = {}
    for index = 1, 500 do lines[index] = "line " .. index end
    lines[460] = "❯ prompt"
    local result = snapshot(lines)
    assert(result.complete and #result.recent_lines == 200 and #result.top_lines == 25)
    assert(#result.bottom_lines == 25 and #result.current_prompt_lines == 25)
    assert(result.recent_lines[1] == "line 301" and result.top_lines[1] == "line 1")
end)
check("normalization/title bound", function()
    local result = snapshot({ "\27]0;" .. string.rep("t", 300) .. "\7" })
    assert(#result.osc_title == 200)
end)

for _, case in ipairs({
    { "codex-cli", "codex" }, { "opencode-cli", "opencode" }, { "claude-code", "claude" },
    { "/opt/bin/codex-cli", "codex" }, { "/opt/claude-code.js", "claude" },
    { "C:\\tools\\CODEX-CLI.EXE", "codex" }, { "C:\\tools\\opencode-cli.cmd", "opencode" },
    { "claude-code.bat", "claude" }, { "codex.mjs", "codex" }, { "opencode.cjs", "opencode" },
}) do
    check("identity/alias/" .. case[1], function()
        assert(process.identify(case[1]) == case[2])
        assert(process.command_agent({ case[1] }) == case[2])
    end)
end
for _, case in ipairs({
    { "env", { "env", "CODEX=1", "codex-cli" }, "codex" },
    { "exec", { "exec", "--", "claude-code" }, "claude" },
    { "sudo", { "sudo", "-u", "fixture", "opencode-cli" }, "opencode" },
    { "timeout", { "timeout", "10s", "codex" }, "codex" },
    { "node", { "node", "/opt/codex-cli.js" }, "codex" },
    { "python", { "python", "/opt/claude-code" }, "claude" },
    { "npx", { "npx", "--package", "fixture", "opencode" }, "opencode" },
    { "nested", { "env", "A=1", "exec", "sudo", "-u", "fixture", "timeout", "2", "node", "codex.js" }, "codex" },
    { "shell echo", { "sh", "-c", "echo codex" } },
    { "shell opaque execution", { "bash", "-lc", "codex" } },
    { "Windows shell", { "cmd.exe", "/c", "echo codex" } },
    { "unrecognized executable", { "echo", "codex" } },
    { "runtime eval", { "node", "--eval", "codex" } },
    { "runtime module", { "python", "-m", "codex" } },
    { "runtime require", { "node", "--require", "codex" } },
    { "runtime attached value", { "node", "--require=codex" } },
    { "runtime unknown option", { "node", "--unrecognized", "codex" } },
    { "runtime script after value", { "node", "--require", "fixture", "codex.js" }, "codex" },
    { "package option value", { "npx", "--package", "codex", "echo" } },
    { "env value only", { "env", "CODEX=codex" } },
    { "sudo option value", { "sudo", "-u", "codex", "echo" } },
    { "timeout duration", { "timeout", "codex" } },
}) do
    check("identity/wrapper/" .. case[1], function()
        local agent = process.command_agent(case[2])
        assert(agent == case[3], "expected " .. tostring(case[3]) .. ", got " .. tostring(agent))
    end)
end

check("identity/shell child", function()
    patched(process, {
        process = function(pid) return pid == 1 and { cmd = { "sh", "-c", "wait" } } or { cmd = { "opencode-cli" } } end,
        children = function(pid) return pid == 1 and { 2 } or {} end,
    }, function() assert(process.tree_agent(1) == "opencode") end)
end)
check("identity/deterministic child selection", function()
    local order = { 30, 20 }
    patched(process, {
        process = function(pid) return { cmd = { pid == 20 and "codex" or pid == 30 and "claude" or "sh" } } end,
        children = function(pid) return pid == 1 and order or {} end,
    }, function()
        local first = process.tree_agent(1)
        order = { 20, 30 }
        assert(process.tree_agent(1) == first, "identity depends on child PID enumeration order")
    end)
end)
for _, depth in ipairs({ 8, 9 }) do
    check("identity/tree depth " .. depth, function()
        local visited = 0
        patched(process, {
            process = function(pid)
                visited = visited + 1
                return { cmd = { pid == depth + 1 and "codex" or "sh" } }
            end,
            children = function(pid) return { pid + 1 } end,
        }, function()
            local agent = process.tree_agent(1)
            assert(agent == (depth == 8 and "codex" or nil))
            assert(visited <= 9)
        end)
    end)
end
check("identity/tree visit bound and cycles", function()
    local visited = 0
    patched(process, {
        process = function() visited = visited + 1; return { cmd = { "sh" } } end,
        children = function(pid) return { pid * 2, pid * 2 + 1, 1 } end,
    }, function()
        assert(process.tree_agent(1) == nil)
        assert(visited == 256, "expected bounded traversal, got " .. visited)
    end)
end)
-- SESS_AGENT is intentionally not asserted: the corpus spec gates that hint
-- on implementation; current process records expose no environment contract.
assert(#failures == 0, "agent_status_corpus failures (" .. #failures .. "):\n" .. table.concat(failures, "\n"))
