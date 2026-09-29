# Agent Instructions

## Purpose

Sess.nvim helps Neovim users save, switch, restore, and manage independent editing contexts for projects and working directories. It preserves project context without requiring users to recreate buffers, windows, cursor positions, working-directory scopes, or terminal state.

The project should remain safe when session data is missing, corrupt, incompatible, or only partially writable. It must also avoid destroying live editor state while switching or unloading sessions.

## Development principles

- Prefer small, focused changes over broad refactors.
- Preserve existing public behavior unless the task explicitly changes the contract.
- Treat filesystem data, user configuration, hook callbacks, autocmds, and editor state as untrusted or fallible inputs.
- Keep lifecycle logic independent of command-line and picker UI code.
- Do not silently repair, delete, overwrite, or discard data to make an operation succeed.
- Avoid adding dependencies unless necessary for the requested behavior.

## Safety and behavior invariants

- Modified buffers, non-file buffers, and running terminal jobs must not be discarded without the required confirmation or safety check.
- Corrupt or incompatible records should be reported and skipped, not silently deleted or repaired.
- Persistence failures must be returned to callers.
- Successful operations may include diagnostics from metadata updates, hooks, or event subscribers.
- State must be committed before post-operation observers run.
- A failing before-transition hook aborts the operation.
- A failing after-operation hook or event subscriber does not undo a committed operation.
- Hooks and event subscribers must not be able to cause recursive lifecycle mutations.
- Public API behavior, user commands, help documentation, and tests must agree.
- User-controlled paths, names, IDs, and targets must be validated before being used for filesystem operations.

## Workflow

1. Read the relevant implementation, tests, and documentation before editing.
2. Identify the behavior contract and failure cases affected by the change.
3. Add or update a focused regression test for behavior changes.
4. Keep UI adapters thin and put shared behavior in the lifecycle/API layer.
5. Update user documentation when public behavior changes.
6. Run the test suite and formatter checks.
7. Review the diff for accidental behavior, safety, or documentation changes.

## Validation commands

Run the test suite:

```sh
sh tests/run.sh
```

Check formatting for changed Lua files:

```sh
stylua --check path/to/changed-file.lua
```

Format changed Lua files when needed:

```sh
stylua path/to/changed-file.lua
```

## Documentation expectations

Document user-facing commands and configuration in the README. Document API contracts, return values, failure behavior, events, and diagnostics in the Neovim help documentation. Update the architecture documentation when ownership or lifecycle boundaries change.

## Review checklist

- Does the change preserve session data on failure?
- Does it handle corrupt or missing data explicitly?
- Does it preserve live buffers, windows, jobs, and editor state where required?
- Are errors and diagnostics distinguishable?
- Are hooks and events run in the documented order?
- Is the behavior covered by an isolated test?
- Are public documentation and examples still accurate?
