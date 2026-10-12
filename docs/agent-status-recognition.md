# Agent Status Recognition Implementation Specification

## Status

Implemented. This document describes the agent-recognition architecture shipped by sess.nvim. It is inspired by Herdr's process detection, screen manifests, lifecycle authority, and explainability, but remains local, dependency-free, and suitable for Neovim Lua.

## Goals

- Improve terminal-agent status accuracy without breaking the existing agent API.
- Keep agent detection process-local and non-persistent.
- Distinguish agent identity from agent status.
- Prefer integration-reported status over screen-derived status.
- Make screen detection agent-specific, ordered, conservative, and explainable.
- Preserve current safety behavior: detection never starts, stops, sends input to, or mutates an agent process.
- Keep discovery usable when process inspection, terminal output, or an integration is unavailable.
- Give users and maintainers enough evidence to diagnose a wrong status.

## Non-goals

- Do not implement a Herdr-compatible daemon or socket protocol.
- Do not add remote manifest downloads in the first implementation.
- Do not persist agent records, terminal output, status history, or integration state.
- Do not automatically answer prompts, approve commands, or send terminal input.
- Do not infer that an agent is `done` from screen text alone in the first version.
- Do not replace the current active-picker lifecycle or UI architecture.
- Do not add a new dependency only to parse a manifest format.

## Current behavior

Agent identity is discovered from terminal jobs and, where possible, their process trees. The status classifier evaluates bounded, agent-specific manifests against structured terminal snapshots. A registered status is authoritative; a registered agent without a status uses the same screen fallback as a detected terminal agent.

The current implementation is split across:

- `lua/sess/agent/process_probe.lua`
- `lua/sess/agent/terminal_probe.lua`
- `lua/sess/agent/status.lua`
- `lua/sess/agent/discovery.lua`
- `lua/sess/api/agent.lua`

The public status strings remain:

```text
idle | working | blocked | done | unknown | integration-defined values
```

## Design overview

```text
terminal buffer
     |
     v
terminal probe -------- process probe
     |                         |
     |                         v
     |                  agent identity
     v
screen snapshot
     |
     v
agent manifest rules
     |
     v
screen observation

integration observation ----+
                             |
                             v
                     status arbitration
                             |
                             v
                    effective agent status
                             |
                             v
                    active picker / API
```

The implementation has four independent concerns:

1. **Identity**: Which known agent, if any, owns this terminal?
2. **Observation**: What does the current terminal screen indicate?
3. **Authority**: Which source is allowed to determine the effective status?
4. **Presentation**: How should the result be shown or explained?

## Status sources and authority

Every effective status must have an internal source:

```lua
---@alias Sess.AgentStatusSource
---| "integration"
---| "screen"
---| "fallback"
---| "unknown"
---| "stale"
```

Authority rules, in order:

1. A fresh explicit integration status wins.
2. A valid screen observation wins when no integration status is authoritative.
3. The agent manifest's default state is used when the agent is known but no rule matches.
4. `unknown` is used when identity is unknown, the terminal cannot be read, or the result cannot be trusted.
5. A stale integration status must not silently remain `working` forever. It is replaced by a valid screen result or reported as stale diagnostics with `unknown`; it is never retained as last-good screen state after a skipped or failed screen probe.

The public `agent.status` field remains a string. Source, rule, evidence, and timestamps are internal observation metadata and are exposed through `api.agent.explain()` rather than added to every normal list row.

### Integration status freshness

A registered or updated status is authoritative until one of the following occurs:

- The integration explicitly updates it.
- The registration is removed.
- Its optional freshness deadline expires.
- The target buffer or terminal job is no longer valid.

The initial compatibility behavior treats a status with no freshness value as session-lifetime authoritative. Future integrations may provide a bounded freshness value. Integration observations are kept separate from the last-good screen observation: a fresh integration result is authoritative for that call but is never retained as screen cache state. A stale status must produce a diagnostic in `explain`, but normal list operations should continue when a screen fallback is available.

## Screen snapshot

`lua/sess/agent/terminal_probe.lua` exposes a bounded structured snapshot instead of only a flat line list.

```lua
---@class Sess.AgentScreen
---@field bufnr integer
---@field changedtick integer?
---@field bottom_lines string[] Recent non-empty terminal lines.
---@field recent_lines string[] Bounded recent terminal lines before trimming.
---@field current_prompt_lines string[] Text after the latest recognized prompt marker.
---@field top_lines string[] Initial non-empty lines useful for startup prompts.
---@field osc_title string? Last safely decoded terminal title, if available.
---@field complete boolean Whether the terminal read completed without an error.
---@field error string? Read diagnostic when complete is false.
```

Requirements:

- Read only a bounded number of lines.
- Trim trailing blank lines before classification.
- Normalize carriage returns.
- Remove ANSI CSI and OSC sequences safely.
- Preserve enough structure to distinguish current prompt content from old transcript text.
- Never treat a terminal title or screen line as executable input.
- Return read errors to the caller as diagnostics, not exceptions escaping discovery.
- Require every line element to be a string; malformed line elements produce diagnostics and an `unknown` observation.

The exact prompt markers are agent-specific. The probe may provide generic candidates, but manifests decide which marker is meaningful for an agent.

## Detection manifests

The implementation uses Lua tables. This avoids a parser dependency and keeps manifests versioned with the plugin. The format is isolated so a future TOML or user-file loader can be added without changing the classifier.

Module:

```text
lua/sess/agent/manifests.lua
```

Example shape:

```lua
return {
    codex = {
        version = 1,
        default = "unknown",
        rules = {
            {
                id = "approval",
                state = "blocked",
                priority = 100,
                region = "current_prompt",
                any = {
                    { contains = "allow command?" },
                    { contains = "[y/n]" },
                },
            },
            {
                id = "working",
                state = "working",
                priority = 50,
                region = "before_current_prompt",
                any = {
                    { contains = "to interrupt" },
                    { regex = "working" },
                },
            },
            {
                id = "idle-prompt",
                state = "idle",
                priority = 10,
                region = "current_prompt",
                contains = "❯",
            },
        },
    },
}
```

### Rule semantics

Each rule has:

- `id`: Stable diagnostic identifier.
- `state`: Resulting semantic state.
- `priority`: Higher values are evaluated first.
- `region`: Snapshot region to inspect.
- One matcher or a boolean matcher expression.
- Optional `evidence` boolean for the explanation result. It defaults to true;
  `false` suppresses evidence for a matching rule. Selected evidence is limited
  to three distinct sanitized lines of at most 240 bytes each.
- Optional `skip_state_update` for transcript/history screens.

Supported matchers in the first version:

- `contains = "text"`
- `contains_any = { "text", "text" }`
- `regex = "pattern"`
- `any = { matcher, matcher }`
- `all = { matcher, matcher }`
- `not = { matcher, matcher }`

Matching is case-insensitive for plain text unless a rule explicitly requests case-sensitive matching. Regex support must use a safe, bounded Lua-compatible pattern implementation. Rules must not execute code.

Supported regions in the first version:

- `current_prompt`
- `before_current_prompt`
- `bottom_non_empty`
- `recent`
- `top_non_empty`
- `osc_title`

A rule that has no matching region or malformed matcher is skipped and produces a diagnostic in explanation mode. One malformed rule must not make discovery fail.

### Evaluation

Rules are sorted by descending priority, then by declaration order. The first matching rule wins.

A matching rule returns:

```lua
{
    state = "blocked",
    source = "screen",
    rule_id = "approval",
    manifest_id = "codex",
    manifest_version = 1,
    evidence = { "allow command?" },
    skip_state_update = false,
}
```

If a transcript rule matches with `skip_state_update = true`, the screen must not replace a previous authoritative state. The explanation should report that screen detection was skipped and why. The built-in Codex, Claude, and OpenCode manifests use separate conservative rules; approval matchers inspect the current prompt region so old transcript text is not treated as a current block.

### Conservative blocked detection

Blocked rules must describe visible, current approval or question UI. Generic historical text such as an old `[y/n]` in scrollback is insufficient.

The classifier should prefer `idle` or `unknown` over a false `blocked` result. This is important because the active picker may direct attention based on blocked status, while sess.nvim must never act on that status automatically.

## Identity detection

The existing process-tree implementation remains the foundation.

Identity lookup order:

1. Direct terminal job command.
2. Terminal job process ID.
3. Descendant process tree, bounded by depth and visited-process count.
4. Terminal name fallback only when it is already a known command.

The detector must:

- Accept common wrappers such as `env`, `exec`, `sudo`, `npm`, `npx`, `pnpm`, `node`, and shells.
- Avoid classifying arbitrary command arguments as an agent unless the executable is a recognized wrapper or shell.
- Bound process-tree traversal.
- Deduplicate visited PIDs.
- Return identity diagnostics when process inspection is unavailable.
- Never trust an arbitrary environment value as a command or path.

Environment hints such as `HERDR_AGENT` are currently unsupported and deferred. Discovery does not read arbitrary environment values for identity, so hints cannot override process-tree or terminal-name detection and cannot add an unknown agent.

## Observation result

The status classifier is a pure module with an injectable manifest and screen snapshot.

API:

```lua
local observation = status.observe({
    name = "codex",
    screen = screen_snapshot,
    manifest = manifest,
})
```

Result:

```lua
{
    state = "working",
    source = "screen",
    rule_id = "working",
    manifest_id = "codex",
    manifest_version = 1,
    evidence = { "to interrupt" },
    skip_state_update = false,
    diagnostics = {},
}
```

Failure behavior:

- Invalid input returns `unknown` with a diagnostic.
- Missing manifest for a recognized agent uses `unknown`, unless a compatibility fallback is explicitly defined for that agent.
- Missing terminal lines do not raise an error.
- Malformed individual rules are skipped and reported.
- No matching rule uses the manifest default.

## Status arbitration

Arbitration belongs in `lua/sess/agent/discovery.lua` or a focused module beside it. It must not be implemented separately by Telescope or commands.

Input:

```lua
{
    integration = integration_observation,
    screen = screen_observation,
    previous = previous_observation,
}
```

Result:

```lua
{
    state = "idle",
    source = "screen",
    previous_state = "working",
    changed = true,
    stale = false,
    diagnostics = {},
}
```

The effective result must be computed on every uncached snapshot. Cached results may be reused only when the identity and terminal `changedtick` are unchanged and the cache TTL is valid.

A changed terminal screen invalidates the status cache even when the process identity is unchanged. A changed process/job identity invalidates both identity and status caches.

## Explain API

Add a read-only API:

```lua
local ok, err, explanation, diagnostics = api.agent.explain(target, agent_id)
```

The target resolution and error contract must match the existing agent API. A successful explanation includes:

```lua
{
    id = "terminal:12",
    name = "codex",
    status = "blocked",
    source = "screen",
    target = { bufnr = 12, winid = 3 },
    identity = {
        source = "job-process-tree",
        command = "codex",
        pid = 1234,
    },
    manifest = {
        id = "codex",
        version = 1,
    },
    matched_rule = {
        id = "approval",
        priority = 100,
    },
    evidence = { "allow command?" },
    screen = {
        changedtick = 42,
        line_count = 8,
        complete = true,
    },
    cache = {
        identity = false,
        status = false,
    },
    diagnostics = {},
}
```

The explanation must not expose unbounded terminal output. If evidence text is included, it must be bounded and sanitized. The normal list API should continue returning compact agent records.

## Integration API compatibility

Existing calls remain valid:

```lua
api.agent.register(nil, {
    id = "agent-1",
    name = "codex",
    bufnr = bufnr,
})

api.agent.update(nil, "agent-1", {
    status = "done",
    info = "finished",
})
```

For the current implementation:

- `status` supplied through `register` or `update` remains authoritative.
- Omitting `status` continues to mean screen-derived fallback for terminal-backed agents.
- Existing integration-defined status strings remain accepted.
- `list()` continues to return defensive copies.
- `snapshot()` and `snapshot_active()` continue to return the same result shape.
- New explanation fields are additive and do not appear in persisted state.

If freshness is implemented, it should use a separate optional field or internal metadata rather than changing the meaning of the existing `status` field.

## Discovery and lifecycle safety

Agent detection remains derived runtime state:

- It does not write storage.
- It does not register detected agents as persistent records.
- It does not mutate editor state.
- It does not focus buffers.
- It does not stop jobs.
- It must tolerate invalid, hidden, or deleted buffers.
- It must preserve the last usable snapshot when a later probe fails.
- Probe errors become diagnostics and do not become uncaught errors in picker refresh callbacks.

Explicit registered records continue to win over a detected record with the same ID or target buffer. A registered record without explicit status may receive a derived status, but the derived value must not be written back as an integration override.

## Active picker behavior

The active picker should keep its current behavior:

- Initial snapshot remains fast and bounded.
- Hydration and refresh use the shared agent API.
- Status changes redraw rows without changing stable selection identities.
- A failed probe retains the last usable rows and displays stale/diagnostic state.
- A vanished agent is removed from the result and selection falls back safely.
- The picker does not show raw matcher internals by default.
- A future action may open `agent.explain()` for the selected agent.

This implementation does not add a new automatic polling strategy. Existing polling and cache behavior is reused.

## Configuration

This release ships built-in manifests only. Optional configuration may be added later with a validated setup field:

```lua
require("sess").setup({
    agents = {
        manifests = {
            codex = {
                -- Validated rule overrides only.
            },
        },
    },
})
```

Configuration must not allow arbitrary Lua functions in screen rules. User overrides should be data-only, bounded, and validated before use. Invalid configuration should be rejected during setup with a clear error rather than silently changing detection semantics.

Remote updates and filesystem-loaded manifests are explicitly out of scope until a safe versioning, validation, and failure policy is designed.

## Testing plan

### Unit tests

Add focused tests for:

- Plain text, regex, `any`, `all`, and `not` matchers.
- Rule priority and declaration-order tie breaking.
- Region selection.
- Case normalization and ANSI-cleaned input.
- Malformed rule isolation.
- Missing manifests and default states.
- Transcript rules with `skip_state_update`.
- Evidence truncation.

### Status regression tests

Extend `tests/cases/agent_status.lua` with:

- Old approval text followed by an idle prompt remains idle.
- A current approval prompt becomes blocked.
- A transcript/history screen does not overwrite the last status.
- Agent-specific rules distinguish Pi, Codex, Claude, and OpenCode patterns.
- A known agent with no matching rule uses its documented default.
- An unknown agent remains unknown.
- An explicit `done` integration status remains authoritative over screen text.
- A changed terminal `changedtick` invalidates the cached status.
- A terminal read failure retains the last usable result and reports a diagnostic.

### Identity tests

Extend `tests/cases/agent_detection.lua` with:

- Shell and wrapper process trees.
- Bounded descendant traversal.
- Cyclic or repeated process references.
- Missing `/proc` data or unavailable job information.
- Environment hints remain unsupported and are not consulted.
- Direct process identity taking precedence over wrapper arguments.

### API tests

Add tests for:

- `api.agent.explain()` success.
- Missing session and missing agent errors.
- Defensive copies from explanation results.
- Bounded evidence and no raw unbounded terminal output.
- Diagnostics separated from operation errors.

### UI tests

Add or update active-picker tests for:

- Source-independent status rendering.
- Stale probe behavior.
- Stable selection after a status-only refresh.
- Explain action discoverability, if an explain action is added.

Run:

```sh
sh tests/run.sh
stylua --check lua/sess/agent lua/sess/api/agent.lua
```

## Implementation phases

### Phase 1: Internal observation model

- Introduce observation result types and status-source constants.
- Preserve the current public list shape.
- Add pure tests around the new result shape.

### Phase 2: Manifest rule engine

- Add built-in Lua manifests.
- Implement bounded regions and matchers.
- Port current generic behavior as compatibility rules.
- Add per-agent manifests for Pi, Codex, Claude, and OpenCode first.

### Phase 3: Discovery arbitration

- Integrate screen observations into discovery.
- Preserve explicit integration authority.
- Add cache invalidation and diagnostics.
- Ensure failed probes retain the last usable result.

### Phase 4: Explain API

- Add `api.agent.explain()`.
- Add help documentation and README examples.
- Keep explanation output bounded and defensive.

### Phase 5: Optional freshness and configuration

- Add integration status freshness only after the basic model is stable.
- Add validated data-only overrides if real use cases justify them.
- Revisit external manifest loading only with a clear trust and update policy.

## Acceptance criteria

The implementation is complete when:

- Existing agent registration, update, list, focus, and picker behavior remains compatible.
- Screen detection is driven by agent-specific ordered rules rather than only global substrings.
- Current approval prompts are detected without treating stale scrollback as blocked.
- Integration statuses remain authoritative according to the documented freshness policy.
- Process and terminal probe failures are returned as diagnostics and do not crash refresh.
- `api.agent.explain()` identifies the status source and matching evidence.
- No agent status operation starts, stops, sends input to, or persists agent processes.
- Focused tests cover identity, rule evaluation, arbitration, caching, failures, and UI refresh behavior.
- User-facing API and help documentation describe the new explanation and status semantics.
