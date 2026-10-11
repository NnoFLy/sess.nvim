# Sess.nvim

Sess.nvim lets you save, switch between, and restore independent Neovim
sessions for your projects and working directories.

It keeps the things that make a workspace feel like yours: buffers, windows,
cursor positions, working directories, and terminal state.

## Installation

Telescope and plenary.nvim are optional. They are only needed for the session
picker.

### lazy.nvim

```lua
{
    "NnoFLy/sess.nvim",
    lazy = false,
    config = function()
        require("sess").setup()
    end,
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-telescope/telescope.nvim",
    },
}
```

### Native packages

```lua
vim.pack.add({
    "https://github.com/NnoFLy/sess.nvim",
    "https://github.com/nvim-lua/plenary.nvim",
    "https://github.com/nvim-telescope/telescope.nvim",
})

require("sess").setup()
```

If you do not need the picker, omit the optional dependencies.

## Configuration

The defaults are ready to use:

```lua
require("sess").setup()
```

A typical customized setup looks like this:

```lua
require("sess").setup({
    -- Directories or glob patterns shown in the picker.
    paths = { "~/code/*" },

    -- Load or create the session for the current directory on startup
    -- when Neovim starts without files or arguments.
    smart_auto_load = true,

    -- Save the current session when Neovim exits, except for excluded filetypes.
    auto_save = true,
    exclude_filetypes = { "gitcommit" },

    log_level = "info", -- debug | info | warn | error
    store_path = vim.fn.stdpath("data") .. "/sess.nvim",

    -- Optional lifecycle callbacks. See Hooks and events below.
    hooks = {},

    -- Global mark mappings.
    keymap = {
        prefix = "<C-q>",
        set_mark = "<C-q>",
        edit_marks = "<C-e>",
    },
})
```

The complete configuration is available in [`:help sess-api.opts`](doc/sessionizer.txt).
Picker options are documented in [`:help sess-telescope`](doc/sessionizer.txt).

Sess.nvim owns the `SessNvimInternal` autocmd group. Use another augroup for
your own autocommands.

## Commands

| Command | Description |
| --- | --- |
| `:Sess create [path]` | Create a session, or load the existing session for that path. |
| `:Sess load [name/id/path/@mark]` | Load a session; path targets create missing sessions. Defaults to the current directory. |
| `:Sess mark @mark [target]` | Assign a persistent mark to a session. |
| `:Sess unmark @mark` | Remove a mark. |
| `:Sess save` | Save the current session. |
| `:Sess last` | Return to the previous session, or the most recently used session after a fresh start. |
| `:Sess unload [target]` | Close buffers and terminal jobs owned exclusively by the target session. |
| `:Sess pin [target]` | Toggle a session's pinned state. |
| `:Sess rename [target] [name]` | Rename a session. Prompts when the name is omitted. |
| `:Sess delete [target]` | Move a session to private trash. |
| `:Sess restore [target]` | Restore a deleted session, or open the restore picker. |
| `:Sess list` | Open the Telescope session picker. |
| `:Sess active` | Open active sessions and their detected or registered agents. |

Add your own mappings if you use the commands frequently:

```lua
vim.keymap.set("n", "<M-s>s", "<cmd>Sess save<cr>")
vim.keymap.set("n", "<M-s>l", "<cmd>Sess list<cr>")
vim.keymap.set("n", "<leader><C-^>", "<cmd>Sess last<cr>")
```

### Marks

Marks are single lowercase letters or digits. The default mappings are:

- `<C-q><key>`: load the session assigned to `key`
- `<C-q><C-q><key>`: assign `key` to the current session
- `<C-q><C-e>`: open the mark manager

Change these mappings with the top-level `keymap` option. Marks can also be
managed with the `mark` and `unmark` commands or the Lua API.

## Switching sessions safely

When switching, Sess.nvim saves the outgoing session and hides its buffers.
Modified buffers, non-file buffers, and running terminal jobs are kept alive.
Switching back to an active session restores its buffers, layout, cursor
positions, buffer listing, and working-directory scopes without reloading the
snapshot.

Sessions share buffers, so opening a file that is already open usually reuses
its buffer. Window IDs and some plugin-specific window settings may change.

Operations are deliberately conservative:

- Corrupt or incompatible records are reported and skipped, never silently
  repaired or deleted.
- Unload refuses to discard unconfirmed edits or running jobs.
- Deleted sessions are moved to private trash and can be restored while their
  metadata remains valid.
- Failed saves and persistence errors are returned to callers.

Run `:checkhealth sess` to check setup, storage access, metadata, and snapshots.

## Lua API

The API is split into session, state, and agent operations:

```lua
local api = require("sess.api")

local ok, err, session, diagnostics = api.session.load("my-project")
if not ok then
    -- The core does not prompt or notify. Handle the error in your UI.
end

api.session.save()
api.session.last()
api.session.unload("my-project")

local current = api.state.current()
local previous = api.state.prev()
local active = api.state.active()
```

Mutating operations return `ok`, an error when they fail, the operation result,
and diagnostic strings. A successful operation can therefore include warnings
from metadata updates, restoration, hooks, or events. State getters return
defensive copies; `api.state.active_generation()` provides the current
read-only active-state generation for detecting stale asynchronous snapshots.

For the full API contract and failure behavior, see
[`:help sess-api`](doc/sessionizer.txt).

### Agents

Agents are process-local and are never persisted. Known terminal agents, such as
`pi` and `codex`, are detected automatically by `:Sess active`. Integrations
can register agents and update their status:

```lua
api.agent.register(nil, {
    id = "agent-1",
    name = "worker",
    bufnr = bufnr,
})

api.agent.update(nil, "agent-1", {
    status = "done",
    info = "finished",
})

api.agent.focus(nil, "agent-1")
```

## Hooks and events

Use hooks to run code around lifecycle operations:

```lua
require("sess").setup({
    hooks = {
        before_transition = function(context)
            -- Throwing aborts create, load, restore, unload, or current-session deletion.
            -- context: { operation, session, current }
        end,
        after_operation = function(context)
            -- State is already committed. Errors become diagnostics.
        end,
    },
})
```

Subscribe to lifecycle events with a `User` autocommand:

```lua
vim.api.nvim_create_autocmd("User", {
    pattern = { "SessLoaded", "SessCreated", "SessUnloaded" },
    callback = function(event)
        local current = event.data.current
        -- event.data also contains operation and session.
    end,
})
```

Available events are `SessCreated`, `SessLoaded`, `SessSaved`, `SessUnloaded`,
`SessDeleted`, `SessRestored`, `SessRenamed`, `SessPinned`, `SessMarked`, and
`SessUnmarked`.

State is committed before `after_operation` runs and before the event fires.
Observers can query state but cannot start another lifecycle mutation. During
exit autosave, persistence still runs but hooks and User events are skipped
because the editor is shutting down. Errors from post-operation hooks and
subscribers do not undo a successful operation.

## Telescope picker

Install Telescope and plenary.nvim, then load the extension:

```lua
require("telescope").load_extension("sess")
```

Optional picker configuration:

```lua
require("telescope").setup({
    extensions = {
        sess = {
            display = {
                mode = "detailed", -- compact | detailed | auto
                compact_width = 100,
                icons = true,
                ascii_fallback = false,
                toggle_key = "<C-g>", -- false disables the density mapping
                show_metadata = true,
                show_agent_summary = true,
                path_style = "full", -- full | relative | short
                -- highlights = { current = "TelescopeResultsIdentifier" },
            },
            preview = {
                enabled = true,
                width = 0.35,
                min_width = 80,
                show_snapshot_summary = true,
                show_agents = true,
                show_editor_summary = true,
                show_action_hint = true,
                max_agents = 8,
            },
            action_help = {
                enabled = true,
                key = "?",
                footer = true,
            },
            search = {
                fields = {
                    "name", "cwd", "mark", "pinned", "last", "current",
                    "active", "agent", "status", "info",
                },
                filters = true,
                sort = "default", -- default | recent | pinned | activity | name
                show_count = true,
                show_sort = true,
                cycle_sort = false, -- true uses <C-s>; a key or { i = key, n = key }
            },
            active = {
                refresh_key = "<C-r>", -- false disables generated refresh
                header_navigation = true,
                next_header_key = "<C-j>",
                previous_header_key = "<C-k>",
            },
        },
    },
})
```

The picker can load, create, pin, mark, rename, unload, delete, and restore
sessions. `compact` rows keep state, mark, name, and a useful path; `detailed`
rows add metadata and agent summaries. `auto` uses the actual results-window
width and switches to compact below `display.compact_width` (100 by default).
By default, `<C-g>` toggles the regular picker between compact and
detailed row density (the default density is `detailed`); set `display.toggle_key`
to another key or `false` to change or disable this mapping. Search covers
names, paths, marks, session state, and agent details. Configure `search.fields`,
`search.filters`, and `search.sort` (`default`, `recent`, `pinned`, `activity`,
or `name`) to control interpretation and ordering; custom sorters still receive
complete searchable ordinals. Name matches rank ahead of path-only matches;
exact name and mark matches rank highest. Malformed filter-looking text remains
ordinary search text.
The default insert/normal mappings include `<C-y>` to copy the selected complete
session path. Search supports practical match counts, interpreted filters (such
as `status:working`), and non-default sort modes without adding status text to
the prompt. The prompt keeps only the `? - help` hint by default.
`search.show_count` and `search.show_sort` remain accepted for compatibility but
are not rendered there.
Set `search.cycle_sort` to `true` (default key `<C-s>`), a key string, or
`{ i = "<key>", n = "<key>" }` to opt into cycling through `default`, `recent`,
`pinned`, `activity`, and `name`. Existing mappings win; use `false` for a mode
to disable it. The mapping preserves the prompt and selected session, agent, or
directory when the order changes.
The active-session picker provides a conflict-safe manual refresh mapping
(`<C-r>` by default) and `<C-o>` to focus a selected agent; these actions are
safe and do not load or unload sessions. Configure `active.refresh_key` with a
key or `false` to replace or disable refresh. With `active.header_navigation`
enabled (the default), `<C-j>` and `<C-k>` move to the next and previous
session headers; configure their keys with `next_header_key` and
`previous_header_key`, or set header navigation to `false`. Generated mappings
are added only when the key is unclaimed, so `active_mappings` and picker
mappings always take precedence. Header arrows indicate expansion state, and
agent summaries include textual loading, stale, blocked, and unknown states. Refresh
preserves prompt, selection, and expansion; a disappeared agent selects its
parent header. Override or disable any mapping with `mappings` or
`active_mappings` (use `false`). The prompt keeps only the `? - help` hint; the
`?` popup describes applicable actions for the selected row, marking row-specific
actions unavailable when they do not apply. The private preview is read-only: it
shows identity, state, and editor statistics when available, plus snapshot
diagnostics, bounded active-agent status, and the
action Enter would perform. `show_snapshot_summary`, `show_agents`,
`show_editor_summary`, and `show_action_hint` independently control those
sections; `max_agents` bounds the agent list. `preview.width` controls the
preview fraction and `min_width` hides it when the result area is too narrow.
Missing or corrupt data is rendered as a warning and does not load, source,
write, or mutate a session. Hydration and refresh failures retain the last
usable rows and expose diagnostics; successful operations may also report
non-fatal diagnostics. Use `:Sess active` for a live view of active sessions
and their agents.

Rows and the help hint use screen-cell widths, so long paths and
Unicode names are truncated without splitting wide characters and without
losing searchable/action values. Narrow terminals collapse secondary labels
and hide the preview when needed. Set `icons = false` or `ascii_fallback = true`
for ASCII markers; semantic highlight groups can be overridden through
`display.highlights` (for example, `{ current = "TelescopeResultsIdentifier" }`).
Symbols and highlights are presentation only: state, marks, names, paths, and
agent statuses remain distinguishable in plain text.

## Development

Run the test suite:

```sh
sh tests/run.sh
NVIM_BIN=/path/to/latest-stable/nvim sh tests/run.sh
```

Format Lua files with `stylua`:

```sh
stylua path/to/file.lua
stylua --check path/to/file.lua
```

The test suite runs Neovim in isolated temporary environments. Telescope is not
required for the tests.
