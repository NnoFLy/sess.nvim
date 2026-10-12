-- Built-in screen manifests are intentionally data-only. The matcher validates
-- this shape before using it, so a bad record cannot execute Lua code.
local compatibility_rules = {
    {
        id = "approval",
        state = "blocked",
        priority = 100,
        region = "current_prompt",
        any = {
            { contains = "action required" },
            { contains = "allow command?" },
            { contains = "do you want to proceed" },
            { contains = "do you want to allow" },
            { contains = "would you like to" },
            { contains = "esc to cancel" },
            { contains = "enter to confirm" },
            { contains = "enter to select" },
            { contains = "[y/n]" },
            { contains = "waiting for permission" },
        },
    },
    {
        id = "working",
        state = "working",
        priority = 50,
        region = "bottom_non_empty",
        any = {
            { contains = "working..." },
            { contains = "working" },
            { contains = " to interrupt" },
            { contains = "── working ──" },
            { regex = "[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] *working" },
        },
    },
    {
        id = "idle-prompt",
        state = "idle",
        priority = 10,
        region = "current_prompt",
        any = {
            { contains = "❯" },
            { contains = "›" },
        },
    },
}

local codex_rules = {
    {
        id = "approval",
        state = "blocked",
        priority = 100,
        region = "current_prompt",
        any = {
            { contains = "action required" },
            { contains = "allow command?" },
            { contains = "would you like to run" },
            { contains = "would you like to" },
            { contains = "do you want to proceed" },
            { contains = "do you want to allow" },
            { contains = "esc to cancel" },
            { contains = "enter to confirm" },
            { contains = "enter to select" },
            { contains = "[y/n]" },
            { contains = "waiting for permission" },
            { all = { { contains = "1. yes" }, { contains = "2. no" } } },
        },
    },
    {
        id = "working",
        state = "working",
        priority = 50,
        region = "bottom_non_empty",
        any = {
            { contains = "working..." },
            { contains = " to interrupt" },
            { regex = "[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] *working" },
        },
    },
    {
        id = "idle-prompt",
        state = "idle",
        priority = 10,
        region = "current_prompt",
        any = {
            { contains = "❯" },
            { contains = "›" },
        },
    },
}

local claude_rules = {
    {
        id = "claude-approval",
        state = "blocked",
        priority = 100,
        region = "current_prompt",
        any = {
            { contains = "action required" },
            { contains = "allow command?" },
            { contains = "do you want to proceed" },
            { contains = "do you want to allow" },
            { contains = "would you like to" },
            { contains = "esc to cancel" },
            { contains = "enter to confirm" },
            { contains = "enter to select" },
            { contains = "[y/n]" },
            { contains = "waiting for permission" },
            { all = { { contains = "1. yes" }, { contains = "2. no" } } },
        },
    },
    {
        id = "claude-working",
        state = "working",
        priority = 50,
        region = "bottom_non_empty",
        any = {
            { contains = "esc to interrupt" },
            { contains = " to interrupt" },
            { contains = "thinking" },
            { contains = "working..." },
        },
    },
    {
        id = "claude-idle-prompt",
        state = "idle",
        priority = 10,
        region = "current_prompt",
        contains = "❯",
    },
}

local opencode_rules = {
    {
        id = "opencode-approval",
        state = "blocked",
        priority = 100,
        region = "current_prompt",
        any = {
            { contains = "action required" },
            { contains = "allow command?" },
            { contains = "do you want to proceed" },
            { contains = "do you want to allow" },
            { contains = "would you like to" },
            { contains = "esc to cancel" },
            { contains = "waiting for permission" },
            { contains = "permission required" },
            { contains = "enter to confirm" },
            { contains = "enter to select" },
            { contains = "[y/n]" },
            { all = { { contains = "allow" }, { contains = "deny" } } },
        },
    },
    {
        id = "opencode-working",
        state = "working",
        priority = 50,
        region = "bottom_non_empty",
        any = {
            { contains = "working..." },
            { contains = "to interrupt" },
            { contains = "thinking" },
            { contains = "running" },
        },
    },
    {
        id = "opencode-idle-prompt",
        state = "idle",
        priority = 10,
        region = "current_prompt",
        any = {
            { contains = "›" },
            { contains = "❯" },
        },
    },
}

local pi_rules = {
    {
        id = "approval",
        state = "blocked",
        priority = 100,
        region = "current_prompt",
        any = {
            { contains = "action required" },
            { contains = "allow command?" },
            { contains = "do you want to proceed" },
            { contains = "do you want to allow" },
            { contains = "would you like to" },
            { contains = "esc to cancel" },
            { contains = "enter to confirm" },
            { contains = "enter to select" },
            { contains = "[y/n]" },
            { contains = "waiting for permission" },
        },
    },
    {
        id = "working",
        state = "working",
        priority = 50,
        region = "bottom_non_empty",
        any = {
            { contains = "working..." },
            { contains = "working" },
            { contains = " to interrupt" },
            { contains = "── working ──" },
            { regex = "[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏] *working" }
        },
    },
    {
        id = "idle-prompt",
        state = "idle",
        priority = 10,
        region = "current_prompt",
        any = {
            { contains = "❯" },
            { contains = "›" },
            { contains = "ready for your next prompt" },
        },
    },
}

return {
    amp = { version = 1, default = "unknown", rules = compatibility_rules },
    agy = { version = 1, default = "unknown", rules = compatibility_rules },
    claude = { version = 1, default = "unknown", rules = claude_rules },
    cline = { version = 1, default = "unknown", rules = compatibility_rules },
    codex = { version = 1, default = "unknown", rules = codex_rules },
    copilot = { version = 1, default = "unknown", rules = compatibility_rules },
    cursor = { version = 1, default = "unknown", rules = compatibility_rules },
    devin = { version = 1, default = "unknown", rules = compatibility_rules },
    droid = { version = 1, default = "unknown", rules = compatibility_rules },
    gemini = { version = 1, default = "unknown", rules = compatibility_rules },
    grok = { version = 1, default = "unknown", rules = compatibility_rules },
    hermes = { version = 1, default = "unknown", rules = compatibility_rules },
    kilo = { version = 1, default = "unknown", rules = compatibility_rules },
    kimi = { version = 1, default = "unknown", rules = compatibility_rules },
    kiro = { version = 1, default = "unknown", rules = compatibility_rules },
    letta = { version = 1, default = "unknown", rules = compatibility_rules },
    maki = { version = 1, default = "unknown", rules = compatibility_rules },
    muse = { version = 1, default = "unknown", rules = compatibility_rules },
    omp = { version = 1, default = "idle", rules = pi_rules },
    opencode = { version = 1, default = "unknown", rules = opencode_rules },
    pi = { version = 1, default = "idle", rules = pi_rules },
    qodercli = { version = 1, default = "unknown", rules = compatibility_rules },
    qwen = { version = 1, default = "unknown", rules = compatibility_rules },
}
