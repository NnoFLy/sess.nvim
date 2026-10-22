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
    smart_auto_load = true,
    auto_save = true,
    exclude_filetypes = { "gitcommit" },
    keymap = {
        prefix = "<C-q>",
        set_mark = "<C-q>",
        edit_marks = "<C-e>",
    },
    sidebar = {
        enabled = true,
        start_open = false,
        position = "left", -- left | right
        width = 32,
        min_width = 24,
        max_width = 48,
        active_expand = "none", -- all | current | none
        toggle_key = false,
        refresh_interval = 1000, -- positive integer milliseconds
        mouse = true,
    },
})
```

`:Sess sidebar` toggles the optional native sidebar. It shows active sessions
and agents, refreshes while open, and preserves selection across tab changes.
The cursor can move freely onto the title, separators, and footer without
refresh snapping it back to a session or agent.
All mappings are fixed, buffer-local normal-mode keys:

| Keys | Action |
| --- | --- |
| `<CR>` | Load session, then focus the selected agent (or remembered agent on a header). |
| `<Tab>` / `<S-Tab>` | Toggle parent expansion / collapse all if any expanded, else expand all. |
| `<C-j>` / `<C-k>` | Next / previous session header. |
| `r` / `<C-r>` | Refresh. |
| `rr` / `uu` / `dd` | Rename / safely unload / confirm deletion. |
| `<C-b>` / `um` | Assign / clear mark. |
| `p` / `<C-y>` | Toggle pin / copy full cwd to the `+` register. |
| `<C-o>` | Focus selected agent without switching (current session only). |
| `<C-s>` | Cycle sort: default → recent → pinned → activity → name. |
| `?` / `q` / `<Esc>` | Scrollable help / close (in help, dismiss help). |

Help lists available actions first, followed by dimmed unavailable actions grouped
under a `▸` heading for each shared reason.

Row actions require the cursor on a real session/agent row; session operations
on agents target their parent. Title, separator, placeholder and footer lines
never act on a remembered selection. Sort is sidebar-local, survives refresh,
and resets on close/reopen. Headers show pins and existing marks. A click
selects and a double-click accepts when mouse reporting is enabled; Sess.nvim
never changes the global `mouse` option. The sidebar stays open after switches,
unloads and deletes, including cancellation/failure. Unload uses the shared
Save/Discard/Cancel and Stop/Cancel safety prompts. Sidebar/help resources are
transient and excluded from session captures. The sidebar does not require
Telescope or provide search, create, restore-deleted, density control or
configurable action keys.

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
| `:Sess last` | Return to the previous or most recently used session. |
| `:Sess unload [target]` | Close resources owned exclusively by a session. |
| `:Sess pin [target]` | Toggle a session's pinned state. |
| `:Sess rename [target] [name]` | Rename a session. |
| `:Sess delete [target]` | Move a session to private trash. |
| `:Sess restore [target]` | Restore a deleted session or open the restore picker. |
| `:Sess mark @mark [target]` | Assign a persistent mark to a session. |
| `:Sess unmark @mark` | Remove a mark. |
| `:Sess list` | Open the Telescope session picker. |
| `:Sess active` | Show active sessions and their agents in Telescope. |
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

The API is split into session and state operations:

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

Agent state is runtime-only and is never stored in session snapshots. Detected
and registered agents are shown by `:Sess active`. See [`:help sess-api`](doc/sessionizer.txt)
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

The tests run Neovim in isolated temporary environments. Telescope is not
required.
