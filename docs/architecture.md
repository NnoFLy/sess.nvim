# Architecture

## Problem

Sess.nvim manages multiple Neovim editing contexts. A session combines a project or working directory with the editor state needed to return to it later. Switching must not lose unsaved buffers, terminal jobs, window state, or session metadata.

Operations coordinate three kinds of state:

1. **Persistent state**: metadata and editor snapshots on disk.
2. **Runtime state**: active sessions, the current and previous sessions, and captured views.
3. **Live editor state**: buffers, windows, tabpages, jobs, cursor positions, and working directories.

They must keep these states consistent while handling filesystem failures, corrupt data, user callbacks, and Neovim errors.

## Boundaries

```text
User commands / Telescope / Lua API
                |
                v
        Session lifecycle
          /      |      \
         v       v       v
      Catalog  Runtime  Editor
         |      state      |
         v        |        v
       Storage <- views <- paths/callbacks
          ^
          marks registry

Read-only application queries such as `api.active.snapshot()` compose runtime
state, marks, detected agents, and diagnostics before UI adapters format rows.
```

### Public entry points

The setup function, Lua API, user commands, User events, and optional Telescope integration are entry points for consumers. They should delegate behavior rather than implement separate versions of session operations.

### Session catalog

The catalog owns session records and metadata operations such as discovery, lookup, creation, renaming, pinning, deletion, restoration, and persistent mark lookup. It validates names, IDs, paths, uniqueness, metadata, and mark registry entries before lifecycle code changes editor state. Mark syntax/value validation lives in domain-neutral `sess.mark`; storage only validates and persists the registry, lifecycle marks owns assignment/replacement semantics, and UI owns prefix parsing, confirmation, and notifications. Marks are independent of snapshots and agent runtime state.

### Lifecycle layers

The lifecycle API is a thin facade over focused modules under `lua/sess/lifecycle/`:

- `target` resolves caller input through the catalog and never trusts caller metadata;
- `observer` runs pre-transition hooks and publishes post-operation hooks/events. Hook callbacks are resolved by the public API and passed in an operation context;
- `operation_scope` owns the transition guard and exception/result boundary;
- `editor_rollback` captures, protects, and restores reversible editor state;
- `commit` applies runtime activation after persistence and editor changes succeed;
- `transaction` is only a compatibility facade for those focused modules;
- `save` coordinates path-based snapshot callbacks, usage metadata, outgoing saves, and save diagnostics;
- `create`, `load`, `unload`, `mutations`, and `marks` own operation-specific catalog/editor/runtime mutations. They receive an operation context and never import the public options API. Mark operations only update the registry and publish observers; loading a mark delegates to `load`.

Operation modules follow this ordering:

1. Validate and resolve the target.
2. Run the pre-transition hook.
3. Revalidate after hooks and outgoing observers when needed.
4. Save outgoing state when needed.
5. Change or capture editor state.
6. Persist metadata or snapshots.
7. Commit runtime state.
8. Run post-operation hooks and emit events.
9. Return errors and diagnostics separately.

The guard remains held through post-operation observers. Rollback is limited to reversible editor changes and never claims to undo arbitrary sourced Vimscript or user callbacks.

### Runtime state

Runtime state is the in-memory source of truth for the current and previous sessions, active sessions, and per-session views. It also owns process-local agent records and focused-agent IDs keyed by canonical session ID. Reads and writes should use defensive copies so callers cannot mutate internal state accidentally. Agents are not initialized from disk and never enter metadata, snapshots, or Vim session files.

### Editor adapter

The editor layer translates between session operations and Neovim state. It captures and restores buffers, windows, tabpages, cursor positions, working-directory scopes, terminal jobs, and editor snapshots. Snapshot methods accept only paths: `write_snapshot(temp_path)` writes to a storage-provided temporary path and `source_snapshot(snapshot_path)` sources a path selected by lifecycle/storage. It does not resolve session IDs, replace files, validate persisted records, or make persistence/UI policy decisions. Its focus helper only validates and focuses buffers already visible in the current session's tabs; it never creates windows or reveals hidden buffers.

### Runtime agents

The agent API validates registrations and delegates focus to the editor adapter. Detection is composed from injectable adapters: `agent/process_probe.lua` reads process/job trees and identifies commands, `agent/terminal_probe.lua` reads terminal jobs/names/output, `agent/status.lua` performs pure output classification, and `agent/discovery.lua` combines probes with runtime views. The active picker performs best-effort discovery of known agent commands in live terminal buffers. Detected terminal agents classify recent visible output as idle, working, blocked, or unknown. This screen classifier is deliberately conservative and only supplies a fallback; an explicit integration status wins. Discovery is derived runtime state: it never starts/stops processes or writes records merely by opening the picker. Focus is explicitly limited to the current session. Unload and delete remove registered agent records only after destructive editor/storage work and runtime state have committed, before observers run. Failed or cancelled operations preserve them. The active picker reads only active runtime sessions, loads through the lifecycle API, and optionally focuses an existing target as a follow-up action.

### Storage

Storage owns the on-disk representation, including metadata, snapshots, session directories, deleted-session entries, and the atomically-written `marks.json` registry. It is responsible for:

- validating filesystem-derived identifiers;
- creating private directories;
- validating metadata and versions;
- atomic metadata and snapshot writes;
- listing records with diagnostics;
- moving deleted records to reversible trash;
- validating and atomically replacing the independent mark registry;
- refusing unsafe paths and malformed records.

Storage failures must be visible to callers. Corrupt records are skipped with diagnostics and are not automatically repaired or removed.

### UI adapters

Commands and Telescope provide input, target selection, confirmation, notifications, and presentation. They should call the shared API/lifecycle implementation so command and picker behavior remain consistent. The UI load-or-create helper validates a directory, then delegates to `api.session.load()` or `api.session.create()` without changing the low-level API contract. The active picker shows headers from `api.active.initial_snapshot()`, then hydrates through `api.active.snapshot_async()` and formats rows. It does not compose marks, agents, focus, or diagnostics. Status-only refreshes reuse loaded marks and cached terminal probes. Command completion and Telescope share read-only directory enumeration.

The mark popup has two private UI owners. `ui/window.lua` validates its
supported floating-window options and action keymap, computes editor-relative
geometry, and owns only the focusable scratch buffer and float. It clamps the
full bordered rectangle to the usable editor area and exposes update/close
operations for resize and failure cleanup. It does not resolve sessions or run
lifecycle operations. `ui/marks.lua` owns the one active popup, origin focus,
assigned-mark listing, buffer-local mappings, prompts, popup-local conditional
undo, cancellation, and close-before-load ordering. It resolves the selected
mark again through the API rather than trusting the rendered session record.
Popup resources are marked transient so editor capture excludes them; they are
never persisted.

## Operation semantics

### Save

Capture the current editor view, write the session snapshot, update usage metadata, update runtime state, then run observers. A metadata warning does not hide a successful snapshot save; it is returned as a diagnostic.

### Load or create

Resolve or create the target, save the outgoing session when applicable, protect the editor transition, restore or initialize the target, commit runtime state, and notify observers. If the editor transition fails, reversible editor state should be restored.

### Unload

Check for modified buffers and running jobs before removing a session from the live editor. Unload must not silently discard user work.

### Delete and restore

Deletion is soft deletion into private trash. Restoration moves persisted data back and does not implicitly load or alter the live editor. Duplicate IDs, names, or working-directory identities must be rejected.

## Observer model

Pre-transition hooks run before a mutating lifecycle operation and may abort it. Post-operation hooks and User autocmd subscribers run after state is committed. Observer failures become diagnostics and must not roll back an otherwise successful operation.

Observers receive defensive payloads containing the operation, affected session, and current session. Recursive lifecycle mutations are rejected while an operation is in progress. Agent register/update/unregister/focus are independent runtime operations but are explicitly rejected while a lifecycle operation is scoped; focus therefore cannot mutate editor state from a transition hook.

## Design rules for future changes

- Keep persistence, lifecycle, editor, state, and UI responsibilities separate.
- Add behavior at the shared lifecycle/API layer instead of duplicating it in commands or Telescope.
- Treat rollback as limited to reversible editor operations; do not claim to undo arbitrary user code or autocmd side effects.
- Preserve the distinction between operation failure and successful operation with diagnostics.
- Add regression tests for both success and failure paths, especially around corruption, partial I/O failure, hooks, events, and unload safety.
