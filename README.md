# Sess.nvim

Sess.nvim saves, switches, and restores independent Neovim sessions for your
projects and working directories.

A session preserves buffers, windows, cursor positions, working directories,
and terminal state.

## Installation

Telescope and plenary.nvim are optional. Install them only if you want the
session picker.

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

If you do not use the picker, omit plenary.nvim and telescope.nvim.

## Configuration

The defaults are ready to use:

```lua
require("sess").setup()
```

A common setup looks like this:

```lua
require("sess").setup({
    paths = {
        "~/code/personal/project",
        "~/code/work/*",
    },
    smart_auto_load = "current", -- current | all | none
    auto_save = true,
    exclude_filetypes = { "gitcommit" },
    keymap = {
        prefix = "<C-q>",
        set_mark = "<C-q>",
        edit_marks = "<C-e>",
    },
    tabline = { enabled = true },
    sidebar = {
        enabled = true,
        start_open = false,
        position = "left", -- left | right
        width = 32,
        min_width = 24,
        max_width = 48,
        active_expand = "all", -- all | current | none
        toggle_key = false,
        refresh_interval = 1000, -- positive integer milliseconds
        mouse = true,
    },
})
```

`smart_auto_load` defaults to `"current"`: at an implicit startup, load the session
for the exact normalized cwd. If none matches, create one only when the startup
editor is empty; meaningful unmanaged state is left untouched. Choose
`"all"` to resume the previous managed editor instance's active sessions, in
recorded order, with its current session visible. Saved-only sessions stay
inactive. Choose `"none"` to disable automatic loading; booleans are rejected.
Omitted/nil configuration uses the default.

Both loading modes skip explicit files/directories, stdin, `-S`, `-c`, `+cmd`,
`--cmd`, late setup, and existing sessions. Typed input before the deferred attempt
cancels restoration; programmatic plugin buffers (even modified), splits, floats,
and cwd/view changes do not. The restored session owns the visible layout.
Displaced startup buffers and terminal jobs remain alive but unlisted: recover
them with `:ls!` and `:buffer N` (ordinary buffer pickers may hide them). They are
not automatically saved or adopted into the restored session. Their old layout
is not retained. Plugins that inject typed input also cancel restoration;
arbitrary destructive sourced code/autocmds cannot be fully rolled back.
Ambiguous lookups or failed loads never create replacements; all mode never falls
back to cwd creation. Unusable resume entries are skipped with warnings;
execution failures stop further restores and retain earlier commits.

Normal managed exits remember active membership and current selection in every
mode, including `"none"`. A never-managed one-off edit leaves history untouched;
unloading every session remembers an empty set. `auto_save` and
`exclude_filetypes` still control current-session exit snapshots, not membership
bookkeeping. Required save failures prevent publication. The last successful
managed exit wins; snapshots and membership are not one transaction.

Resume uses ordinary saved snapshots, not historical backups or live process
recovery. Keep the store private: resume history is validated data, but ordinary
session snapshots execute trusted Vimscript. Corrupt history is reported without
repair or deletion. See `:help sess-resume` for ordering and failure details.

`:Sess sidebar` toggles the optional native sidebar. It shows active sessions
and agents plus persistent terminals, refreshes while open, and preserves selection
across tab changes. Sidebar sessions and the background group start expanded,
including groups added while it is open; the active picker starts collapsed.
Refresh preserves manual expansion choices.
Active owners show terminal children alongside explicit/detected agents. A final expandable
**Background terminals** group contains inactive owners’ and unassigned terminals,
with owner labels. Inventory never activates a session. Terminal execution states
(`running`, `completed`, `unknown`) are separate from agent work status.
The cursor can move freely onto the title, separators, and footer without
refresh snapping it back to a session or agent.
The footer shows `sort: <state>`, a blank line, then `? - Help`.
All mappings are fixed, buffer-local normal-mode keys:

| Keys | Action |
| --- | --- |
| `<CR>` | Load/focus a session or agent; reconnect a terminal; expand Background terminals. |
| `<Tab>` / `<S-Tab>` | Toggle parent expansion / collapse all if any expanded, else expand all. |
| `<C-j>` / `<C-k>` | Next / previous group header. |
| `r` / `<C-r>` | Refresh. |
| `rr` / `uu` / `dd` | Rename / safely unload / confirm deletion. |
| `<C-b>` / `um` | Assign / clear mark. |
| `p` / `<C-y>` | Toggle pin / copy full cwd to the `+` register. |
| `<C-o>` | Focus selected agent without switching (current session only). |
| `<C-s>` | Cycle sort: default → recent → pinned → activity → name. |
| `?` / `q` / `<Esc>` | Scrollable help / close (in help, dismiss help). |

Help lists available actions first, followed by dimmed unavailable actions grouped
under a `▸` heading for each shared reason.

Session actions require the cursor on a real session/agent row; session operations
on agents target their parent. Terminal rows only reconnect/focus; the background
header Enter only expands; Tab toggles expansion. Title, separator and footer lines
never act on a remembered selection. Sort is sidebar-local, survives refresh,
and resets on close/reopen. Headers show pins and existing marks. A click
selects and a double-click accepts when mouse reporting is enabled; Sess.nvim
never changes the global `mouse` option. The sidebar stays open after switches,
unloads and deletes, including cancellation/failure. Unload uses the shared
Save/Discard/Cancel and Stop/Cancel safety prompts. Sidebar/help resources are
transient and excluded from session captures. The sidebar does not require
Telescope or provide search, create, restore-deleted, density control or
configurable action keys.

### Native tabline

Setup defaults to `tabline = { enabled = true }`. It decorates an existing
custom native tabline without changing its dynamic content, click targets or
highlights. When `vim.o.tabline` is empty, Sess supplies a clickable tab list.
To opt out entirely:

```lua
require("sess").setup({ tabline = { enabled = false } })
```

`enabled` is the only tabline option and must be boolean. Disabling it leaves
both `tabline` and `showtabline` untouched. Setup is one-shot. Sandboxed providers
and raw script-local references are left unchanged, with a warning; explicit
`<SNR>` references are supported. Providers installed later are not rewrapped.
Sess.nvim never changes `showtabline`: `0` hides the tabline, `1` shows it only
with multiple tabs, and `2` always shows it.

When the native tabline is visible, `ACTIVE SESSIONS` moves above the sidebar,
matching its displayed width and edge. It stays there across tab switches and
resizing without flashing inside the sidebar. Tabs retain native click targets
and selected-tab highlights. Sess's labels safely display filenames from each
tab's focused editing window, remembering it while Sess transient UI is focused.
Closing the sidebar leaves the tab list in place. Hidden, replaced, or externally
drawn tablines keep the in-buffer heading instead. No tabline plugin is required;
third-party provider configuration is unchanged.
See `:help sess-tabline` for fallback and low-level helper contracts.

See [`:help sess-api.opts`](doc/sessionizer.txt) for all options and
[`:help sess-telescope`](doc/sessionizer.txt) for picker options.

Sess.nvim owns the `SessNvimInternal` autocmd group. Use a different augroup
for your own autocommands.

## Commands

| Command | Description |
| --- | --- |
| `:Sess create [path]` | Create or load the session for a path. |
| `:Sess load [name/id/path/@mark]` | Load a session. Defaults to the current directory. |
| `:Sess save` | Save the current session. |
| `:Sess term [command]` | Launch a persistent shell or shell command in a terminal view. |
| `:Sess last` | Return to the previous or most recently used session. |
| `:Sess unload [target]` | Close resources owned exclusively by a session. |
| `:Sess pin [target]` | Toggle a session's pinned state. |
| `:Sess rename [target] [name]` | Rename a session. |
| `:Sess delete [target]` | Move a session to private trash. |
| `:Sess restore [target]` | Restore a deleted session or open the restore picker. |
| `:Sess mark @mark [target]` | Assign a persistent mark to a session. |
| `:Sess unmark @mark` | Remove a mark. |
| `:Sess list` | Open the Telescope session picker. |
| `:Sess active` | Show active sessions, agents and persistent terminals in Telescope. |
| `:Sess sidebar` | Toggle the optional native active-session sidebar. |

For example:

```lua
vim.keymap.set("n", "<M-s>s", "<cmd>Sess save<cr>")
vim.keymap.set("n", "<M-s>l", "<cmd>Sess list<cr>")
vim.keymap.set("n", "<leader><C-^>", "<cmd>Sess last<cr>")
```

### Marks

Marks are single lowercase letters or digits. The default mappings are:

- `<C-q><key>` loads the session assigned to `key`.
- `<C-q><C-q><key>` assigns `key` to the current session.
- `<C-q><C-e>` opens the mark manager.

You can also manage marks with `:Sess mark`, `:Sess unmark`, or the Lua API.

## Persistent terminals

Install `tmux` separately and make it available on `PATH` to use `:Sess term`.
No tmux is needed for ordinary session operations. Missing tmux is an error;
Sess.nvim never substitutes a nonpersistent local job.

```vim
:Sess term
:Sess term printf '%s\n' "hello world" | tee output.txt
```

With no command, open an interactive shell using Neovim's `shell` option. With
a command, pass the original shell text, including quoting, pipes and redirects,
to that shell. Both use the invoking window's effective cwd (`lcd`, then `tcd`,
then global cwd). The current session is the optional terminal owner. Without
one, the terminal is unassigned; launching never creates a session.

Each launch creates a distinct execution. Each view is an ordinary Neovim
terminal attachment to the plugin's private tmux server, independent of your
usual tmux server. Closing a view, wiping its buffer, switching or unloading
sessions, and exiting Neovim leave the execution alive. Completed output stays
available for inspection. This is not reboot or backend-loss recovery; work
does not advance while the host sleeps.

Find surviving launched terminals in the sidebar or `:Sess active`, including
from a fresh Neovim instance. Selecting a terminal calls `api.terminal.focus(id)`:
it reuses/reconnects a verified execution, loading its owner through ordinary
session safety checks first. Unassigned work opens without creating/activating a
session. Completed executions reopen read-only output, not a job. Captures over
64 KiB fail with an error without opening output; they are not truncated.
Failed inventory queries retain uncertain identities as unknown/unavailable with
diagnostics; they are not evidence of deletion. Explicit `api.terminal.attach(id)` still opens
an independent view without loading an owner. No selection replays a command.

Saved layouts contain inert synthetic references, not commands to replay.
Automatic view restoration, adoption of remote-created windows, remote collection,
and stop/delete controls are deferred. Until those controls exist, deleting an owner with surviving terminals or incomplete associations is
refused. Ordinary terminal jobs still need the usual Stop confirmation on
unload. See `:help sess-terminal` for results, failures and trust limits.

## Safe switching

When switching, Sess.nvim saves the outgoing session and hides its buffers.
Modified buffers, non-file buffers, and running terminal jobs remain alive.
Switching back restores the session without reloading its snapshot.

Sessions can share buffers, so a file that is already open is usually reused.
Window IDs and some plugin-specific window settings may change.

Sess.nvim reports and skips corrupt or incompatible records. It does not
silently repair or delete them. Unload refuses to discard unconfirmed edits or
running jobs, and persistence failures are returned to callers.

Run `:checkhealth sess` to check setup, storage access, metadata, and snapshots.

## Lua API

The API provides session, state, agent and terminal operations:

```lua
local api = require("sess.api")

local ok, err, session, diagnostics = api.session.load("my-project")
if not ok then
    -- The core does not prompt or notify. Handle errors in your UI.
end

api.session.save()
api.session.last()
api.session.unload("my-project")

local current = api.state.current()
local previous = api.state.prev()
local active = api.state.active()
```

Mutating operations return `ok`, an error when they fail, the operation result,
and diagnostic strings. Successful operations may include warnings from
metadata updates, restoration, hooks, or events. State getters return
defensive copies.

Persistent-terminal operations take no options or hook overrides. Focus uses the
ordinary configured session lifecycle when loading an owner:

```lua
local ok, err, item, diagnostics = api.terminal.launch("make test")
if ok then
    api.terminal.focus(item.id) -- safe owner load, then reuse/reconnect
    -- api.terminal.attach(item.id) opens another independent attachment instead.
end
-- Success: true, nil, { id, execution, bufnr, job_id }, diagnostics
-- Failure: false, error (a committed execution may still survive).
local listed, list_err, entries, warnings = api.terminal.list()
-- entries: { id, owner_id?, owner_name?, name, execution_state, available }
-- Failures retain uncertain identities as unknown/unavailable.
```

Agent state is runtime-only and is never stored in session snapshots. Automatic
agent detection excludes managed attachment views; explicit buffer registrations
remain supported. Detected and registered agents are shown by `:Sess active`. See [`:help sess-api`](doc/sessionizer.txt)
for the agent integration API and full failure behavior.

## Hooks and events

Use hooks to run code around lifecycle operations:

```lua
require("sess").setup({
    hooks = {
        before_transition = function(context)
            -- Throwing aborts the operation.
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
    end,
})
```

Available events are `SessCreated`, `SessLoaded`, `SessSaved`, `SessUnloaded`,
`SessDeleted`, `SessRestored`, `SessRenamed`, `SessPinned`, `SessMarked`, and
`SessUnmarked`.

State is committed before post-operation hooks and events run. A failing
before-transition hook aborts the operation; failures in post-operation hooks
or subscribers become diagnostics and do not undo a successful operation.

## Telescope picker

After installing Telescope and plenary.nvim, load the extension:

```lua
require("telescope").load_extension("sess")
```

The picker can load, create, pin, mark, rename, unload, delete, and restore
sessions. It supports search, sorting, session previews, and a separate active
session view. Configure it with `:help sess-telescope`.

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

The tests run Neovim in isolated temporary environments. Real `tmux` is
required for terminal regressions; a missing executable fails those tests. Each
terminal test cleans up only its private server, even after assertions fail.
Telescope is not required.
