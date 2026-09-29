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
       Storage <- views <- snapshots
```

### Public entry points

The setup function, Lua API, user commands, User events, and optional Telescope integration are entry points for consumers. They should delegate behavior rather than implement separate versions of session operations.

### Session catalog

The catalog owns session records and metadata operations such as discovery, lookup, creation, renaming, pinning, deletion, and restoration. It validates names, IDs, paths, uniqueness, and metadata before lifecycle code changes editor state.

### Lifecycle coordinator

The lifecycle layer coordinates create, load, save, unload, delete, restore, and rename operations. It defines this ordering:

1. Validate and resolve the target.
2. Run the pre-transition hook.
3. Save outgoing state when needed.
4. Change or capture editor state.
5. Persist metadata or snapshots.
6. Commit runtime state.
7. Run post-operation hooks and emit events.
8. Return errors and diagnostics separately.

It also owns busy-state protection and rollback of reversible editor changes when an operation fails.

### Runtime state

Runtime state is the in-memory source of truth for the current and previous sessions, active sessions, and per-session views. Reads and writes should use defensive copies so callers cannot mutate internal state accidentally.

### Editor adapter

The editor layer translates between session operations and Neovim state. It captures and restores buffers, windows, tabpages, cursor positions, working-directory scopes, terminal jobs, and snapshot information. It must not make persistence or UI policy decisions.

### Storage

Storage owns the on-disk representation, including metadata, snapshots, session directories, and deleted-session entries. It is responsible for:

- validating filesystem-derived identifiers;
- creating private directories;
- validating metadata and versions;
- atomic metadata and snapshot writes;
- listing records with diagnostics;
- moving deleted records to reversible trash;
- refusing unsafe paths and malformed records.

Storage failures must be visible to callers. Corrupt records are skipped with diagnostics and are not automatically repaired or removed.

### UI adapters

Commands and Telescope provide input, target selection, confirmation, notifications, and presentation. They should call the shared API/lifecycle implementation so command behavior and picker behavior remain consistent.

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

Observers receive defensive payloads containing the operation, affected session, and current session. Recursive lifecycle mutations are rejected while an operation is in progress.

## Design rules for future changes

- Keep persistence, lifecycle, editor, state, and UI responsibilities separate.
- Add behavior at the shared lifecycle/API layer instead of duplicating it in commands or Telescope.
- Treat rollback as limited to reversible editor operations; do not claim to undo arbitrary user code or autocmd side effects.
- Preserve the distinction between operation failure and successful operation with diagnostics.
- Add regression tests for both success and failure paths, especially around corruption, partial I/O failure, hooks, events, and unload safety.
