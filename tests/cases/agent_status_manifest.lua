local status = require("sess.agent.status")

local function screen(fields)
    fields = fields or {}
    fields.complete = true
    return fields
end

local manifest = {
    version = 7,
    default = "idle",
    rules = {
        { id = "low", state = "done", priority = 10, region = "recent", contains = "ready" },
        { id = "tie-first", state = "working", priority = 20, region = "bottom_non_empty", contains = "busy" },
        { id = "tie-second", state = "done", priority = 20, region = "bottom_non_empty", contains = "busy" },
        {
            id = "boolean",
            state = "blocked",
            priority = 100,
            region = "current_prompt",
            all = {
                { any = { { contains = "question" }, { contains = "confirm" } } },
                { ["not"] = { contains = "cancelled" } },
            },
        },
        { id = "pattern", state = "working", priority = 30, region = "recent", regex = "work%p+ing" },
        { id = "transcript", state = "working", priority = 25, region = "before_current_prompt", contains = "history", skip_state_update = true },
        { state = "blocked", priority = 1000, region = "recent", contains = "bad" },
        { id = "bad-region", state = "blocked", priority = 1000, region = "missing", contains = "bad" },
        { id = "bad-regex", state = "blocked", priority = 1000, region = "recent", regex = "[" },
    },
}

local observed = status.observe({
    name = "fixture",
    manifest = manifest,
    screen = screen({
        recent_lines = { "history: working", "Question: proceed?" },
        bottom_lines = { "history: working", "Question: proceed?" },
        current_prompt_lines = { "Question: proceed?" },
    }),
})
assert(observed.state == "blocked")
assert(observed.source == "screen")
assert(observed.rule_id == "boolean")
assert(observed.manifest_id == "fixture")
assert(observed.manifest_version == 7)
assert(observed.skip_state_update == false)
assert(#observed.diagnostics == 3, vim.inspect(observed.diagnostics))
assert(observed.evidence[1] == "Question: proceed?")

local hidden_evidence = status.observe({
    name = "fixture",
    manifest = {
        version = 1,
        default = "idle",
        rules = {
            { id = "hidden", state = "blocked", priority = 1, region = "recent", contains = "secret", evidence = false },
        },
    },
    screen = screen({ recent_lines = { "secret details" } }),
})
assert(hidden_evidence.state == "blocked" and #hidden_evidence.evidence == 0, vim.inspect(hidden_evidence))

observed = status.observe({
    name = "fixture",
    manifest = manifest,
    screen = screen({
        recent_lines = { "old transcript", "ready" },
        bottom_lines = { "old transcript", "ready" },
        current_prompt_lines = {},
    }),
})
assert(observed.state == "done" and observed.rule_id == "low", vim.inspect(observed))

observed = status.observe({
    name = "fixture",
    manifest = manifest,
    screen = screen({
        recent_lines = { "history: working", "❯ " },
        bottom_lines = { "history: working", "❯ " },
        current_prompt_lines = {},
    }),
})
assert(observed.state == "working" and observed.rule_id == "transcript")
assert(observed.skip_state_update == true)

observed = status.observe({
    name = "fixture",
    manifest = manifest,
    screen = screen({
        recent_lines = { "busy" },
        bottom_lines = { "busy" },
        current_prompt_lines = {},
    }),
})
assert(observed.rule_id == "tie-first" and observed.state == "working")

local built_in = status.observe({
    name = "codex",
    screen = screen({
        recent_lines = { "old approval: Allow command? [y/n]" },
        current_prompt_lines = {},
    }),
})
assert(built_in.state == "unknown", vim.inspect(built_in))

built_in = status.observe({
    name = "codex",
    screen = screen({ current_prompt_lines = { "\27[31mAllow command? [y/n]\27[0m" } }),
})
assert(built_in.state == "blocked")
assert(built_in.evidence[1] == "Allow command? [y/n]")

-- Each supported agent has a separate conservative manifest. Approval text in
-- old scrollback is not enough evidence, while its current UI remains useful.
local agent_fixtures = {
    {
        name = "codex",
        working = "• Working (2s) · esc to interrupt",
        approval = "Action Required: Allow command? [y/n]",
        prompt = "❯",
    },
    {
        name = "claude",
        working = "✳ Thinking...",
        approval = "Do you want to proceed? [y/n]",
        prompt = "❯",
    },
    {
        name = "opencode",
        working = "Thinking...",
        approval = "Permission required: Allow command? [y/n]",
        prompt = "›",
    },
}
for _, fixture in ipairs(agent_fixtures) do
    local old = status.observe({
        name = fixture.name,
        screen = screen({ recent_lines = { "old " .. fixture.approval }, current_prompt_lines = {} }),
    })
    assert(old.state == "unknown", fixture.name .. ": " .. vim.inspect(old))

    local current = status.observe({
        name = fixture.name,
        screen = screen({ bottom_lines = { fixture.working }, current_prompt_lines = {} }),
    })
    assert(current.state == "working", fixture.name .. ": " .. vim.inspect(current))

    current = status.observe({
        name = fixture.name,
        screen = screen({ current_prompt_lines = { fixture.approval } }),
    })
    assert(current.state == "blocked", fixture.name .. ": " .. vim.inspect(current))

    current = status.observe({
        name = fixture.name,
        screen = screen({ current_prompt_lines = { fixture.prompt } }),
    })
    assert(current.state == "idle", fixture.name .. ": " .. vim.inspect(current))
end

local malformed_line = status.observe({
    name = "codex",
    screen = screen({ recent_lines = { "safe line", 42 }, current_prompt_lines = {} }),
})
assert(malformed_line.state == "unknown")
assert(#malformed_line.diagnostics > 0)

local fallback = status.observe({
    name = "pi",
    screen = screen({ recent_lines = { "unrecognised" }, current_prompt_lines = {} }),
})
assert(fallback.state == "idle" and fallback.source == "fallback")
assert(#fallback.diagnostics == 0, vim.inspect(fallback.diagnostics))

local missing = status.observe({ name = "not-an-agent", screen = screen({}) })
assert(missing.state == "unknown" and #missing.diagnostics > 0)

local invalid = status.observe({ name = "fixture", manifest = {}, screen = screen({}) })
assert(invalid.state == "unknown" and #invalid.diagnostics > 0)

local malformed = status.observe({
    name = "codex",
    screen = screen({ bottom_lines = "old scrollback", current_prompt_lines = {} }),
})
assert(malformed.state == "unknown" and #malformed.diagnostics > 0, vim.inspect(malformed))
malformed = status.observe({
    name = "codex",
    screen = screen({ bottom_lines = {}, current_prompt_lines = "not-lines" }),
})
assert(malformed.state == "unknown" and #malformed.diagnostics > 0, vim.inspect(malformed))
malformed = status.observe({
    name = "codex",
    screen = { complete = "yes", recent_lines = {} },
})
assert(malformed.state == "unknown" and #malformed.diagnostics > 0, vim.inspect(malformed))
malformed = status.observe({
    name = "codex",
    screen = { complete = true, osc_title = string.rep("x", 1001), recent_lines = {} },
})
assert(malformed.state == "unknown" and #malformed.diagnostics > 0, vim.inspect(malformed))
malformed = status.observe({
    name = "codex",
    manifest = {
        version = 1,
        default = "idle",
        rules = {
            { id = "bounded", state = "blocked", priority = 1, region = "recent", contains = string.rep("x", 257) },
        },
    },
    screen = screen({ recent_lines = { "safe" } }),
})
assert(malformed.state == "idle" and #malformed.diagnostics > 0, vim.inspect(malformed))
