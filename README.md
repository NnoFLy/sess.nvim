# Sess.nvim

Save and switch Neovim sessions.

## Installation

Telescope and plenary.nvim are only needed for the picker.

```lua
-- lazy.nvim
{
    "NnoFLy/sess.nvim",
    lazy = false,
    config = function()
        require("sess").setup()
    end,
    -- Optional, only for the session picker:
    dependencies = { "nvim-lua/plenary.nvim", "nvim-telescope/telescope.nvim" },
}
```

Or with native packages:

```lua
vim.pack.add({
    "https://github.com/NnoFLy/sess.nvim",
    -- Optional, only for the session picker:
    "https://github.com/nvim-lua/plenary.nvim",
    "https://github.com/nvim-telescope/telescope.nvim",
})
require("sess").setup()
```

## Configuration

```lua
require("sess").setup({
    paths = {}, -- project directories or glob patterns shown in the picker
    smart_auto_load = true, -- load/create for cwd when starting without arguments
    auto_save = true, -- save the current snapshot on exit
    exclude_filetypes = { "gitcommit" }, -- skip exit saves for these filetypes
    log_level = "info", -- debug | info | warn | error
    store_path = vim.fn.stdpath("data") .. "/sess.nvim",
    hooks = {}, -- optional before_transition and after_operation callbacks
})

-- Telescope configuration:
require("telescope").setup({
    extensions = {
        sess = {
            active_expand = "all", -- all | current | none
            -- Override regular or active picker mappings when needed.
            -- mappings = { i = { ["<C-b>"] = ... } },
            -- active_mappings = { i = { ["<C-b>"] = ... } },
        },
    },
})
```

sess.nvim owns the reserved `SessNvimInternal` autocmd group. Use a different
augroup for user autocmds.

## Usage

| Command | Behavior |
| --- | --- |
| `:Sess create [path]` | Create a session, or load the existing one for that path |
| `:Sess load [name/id/path/@mark]` | Load or create a session for the target; defaults to current cwd |
| `:Sess mark @mark [target]` | Assign a persistent mark to the current or named session |
| `:Sess unmark @mark` | Remove a persistent mark |
| `:Sess save` | Save the current session |
| `:Sess last` | Return to the previous session, or open the most recently used session after a fresh start |
| `:Sess unload [name/id/path]` | Close a session's buffers and terminal jobs; defaults to current |
| `:Sess pin [target]` | Toggle pin; defaults to current session |
| `:Sess rename [target] [name]` | Rename; prompts for a missing name |
| `:Sess delete [target]` | Move to private trash; defaults to current session |
| `:Sess restore [target]` | Restore from trash, or open the deleted-session picker |
| `:Sess list` | Open the session Telescope picker |
| `:Sess active` | Open active runtime sessions and detected/registered agents |

```lua
vim.keymap.set("n", "<M-s>s", "<cmd>Sess save<cr>")
vim.keymap.set("n", "<M-s>l", "<cmd>Sess list<cr>")
vim.keymap.set("n", "<leader><C-^>", "<cmd>Sess last<cr>")
vim.keymap.set("n", "<C-q>", require("sess").goto_mark, {
    desc = "Sess: goto mark",
    silent = true,
})
```

### Switching and saving

Switching saves the outgoing snapshot and hides its buffers. Modified named/unnamed buffers, non-file buffers and terminal jobs stay alive. Returning to a still-active session restores buffer identities, layout, cursor positions, buffer listing and cwd scopes without reloading the snapshot.

Sessions share buffers: opening the same file generally reuses its buffer. Window IDs may change, and some plugin/window-local settings can't be restored. User autocommands or trusted code can still delete buffers or stop jobs. Buffers opened before the first session are hidden but remain manually accessible.

## Lua API

```lua
local api = require("sess.api")
local ok, err, item, diagnostics = api.session.load("my-project")
if not ok then
    -- Operation failed. The core does not prompt or notify.
elseif #diagnostics > 0 then
    -- Operation succeeded, but restoration, metadata updates or observers reported errors.
end

api.session.save() -- current session only
api.session.last() -- previous session, or most recently used after a fresh start
api.session.unload("my-project") -- omit target for current; refuses unconfirmed edits/jobs
local current = api.state.current()
local previous = api.state.prev()
local active = api.state.active()
local ok, err, sessions, diagnostics = api.session.list()
local ok, err, deleted, diagnostics = api.session.list_deleted()
api.session.restore("name-or-id-or-trash-key")
local ok, err, marked, diagnostics = api.session.get_by_mark("s")
local ok, err, marks, diagnostics = api.session.list_marks()
api.session.set_mark("project", "s", { replace = true })
api.session.clear_mark("s")

-- Agents are process-local and never persisted. Known agent terminal jobs
-- (for example pi and codex) are detected automatically by :Sess active.
-- Terminal agents get a best-effort idle/working/blocked/unknown status from
-- their visible screen; integrations can override it explicitly.
api.agent.register(nil, { id = "agent-1", name = "worker", bufnr = bufnr })
api.agent.update(nil, "agent-1", { status = "done", info = "finished" })
api.agent.focus(nil, "agent-1")
local ok, err, agents, diagnostics = api.agent.list()
```

Mutations return `(ok, err, session, diagnostics)`, with diagnostic strings on success. Loading the current session succeeds without saves, hooks or events. State getters return defensive copies.

Listing returns `false` for store-wide failures; corrupt records are skipped with diagnostics, never repaired or deleted automatically. Create/rename refuse to claim uniqueness with damaged metadata. `api.items.get_items()` returns `(items, err, diagnostics)`; UI adapters report diagnostics.

`api.session.get_by_name()` and `get_by_path()` return
`(ok, err, session, diagnostics)`. A unique healthy match remains usable when
unrelated records are corrupt, while duplicate names or project paths fail with
an ambiguity error. Lookup diagnostics are always returned.

Marks are one lowercase ASCII letter or digit, persist in a separate atomic
registry, and can point to inactive sessions. Stale marks remain visible in
`list_marks()` until explicitly replaced or removed. The core API never prompts;
commands and Telescope confirm replacement. `:Sess load @s` resolves through the
normal load lifecycle. `require("sess").goto_mark()` reads one following key
when called without an argument, and never installs a mapping automatically.

See [`:help sess-api`](doc/sessionizer.txt) for its contract and failure behavior.

## Hooks and events

```lua
require("sess").setup({
    hooks = {
        before_transition = function(context)
            -- context: { operation, session, current }
            -- Throw to abort create/load/unload/current-session deletion.
        end,
        after_operation = function(context)
            -- State is committed. Throwing only adds a diagnostic.
        end,
    },
})

vim.api.nvim_create_autocmd("User", {
    pattern = { "SessLoaded", "SessCreated", "SessUnloaded", "SessRenamed" },
    callback = function(event)
        local current = event.data.current
        -- Also available: event.data.operation and event.data.session.
        -- For a statusline, read vim.g.sess_current_session.
    end,
})
```

Events: `SessCreated`, `SessLoaded`, `SessSaved`, `SessUnloaded`, `SessDeleted`, `SessRestored`, `SessRenamed`, `SessPinned`, `SessMarked`, `SessUnmarked`.

State commits before `after_operation`, then the event fires. Outgoing saves emit `SessSaved` first. Create emits only `SessCreated`; switching doesn't emit `SessUnloaded`. Explicit unload does, as does current-session deletion before `SessDeleted`. Other deletions emit only `SessDeleted`.

Payloads are defensive `{ operation, session, current }` records; `current` may be nil. Mark events also include `mark` and `session_id`, and replacement includes `previous_id`. Unmarking a stale mark may have a nil `session`. Hooks/events allow queries but reject recursive mutations. Post-hook/subscriber errors don't undo success. Subscriber execution follows Neovim's autocmd rules: Neovim may display errors, and those exposed through its API or `v:errmsg` become diagnostics.

## Telescope

Install telescope.nvim and plenary.nvim, then:

```lua
require("telescope").load_extension("sess")
```

All Sess pickers display results top-to-bottom with the input prompt at the top.
Enter loads/creates. Ctrl-d (insert) or `dd` (normal) deletes with confirmation.
`:Sess restore` opens a deleted-session picker; Enter restores the selected record.
`:Sess active` shows active sessions as tree-style groups with their cwd and
agents. Sessions are expanded by default; configure the Telescope extension's
`active_expand` option as `"all"`, `"current"`, or `"none"`. `<Tab>`
expands/collapses the selected group and `<S-Tab>` expands/collapses all groups.
The picker footer lists these controls and `<Enter>` to switch and focus an
agent. Active picker mappings are configured through `active_mappings`, while
regular picker mappings use `mappings`. Empty groups show a non-actionable `no agents` row. `<C-b>` prompts for
a mark on the selected session in both regular and active pickers. Marks are
shown in a stable leading column on regular rows and on active session
headers. It detects known agent commands running in terminal buffers, including
`pi`, `codex`, `claude`,
and `opencode`; integrations can also register agents through
`api.agent.register()`. Known terminal agents show a best-effort `idle`,
`working`, `blocked`, or `unknown` status based on recent terminal output. The
active picker polls and redraws changed statuses while it is open. Explicit
status updates remain authoritative. Enter loads the selected session and
focuses its existing agent buffer when visible. Agents are runtime-only: this
picker never starts processes, creates windows, or persists agent data. Commands,
Telescope and autocommands use the same lifecycle.

`:Sess load` defaults to the current working directory. `:Sess mark @s` marks
the current session, `:Sess mark @s project-api` marks a specific session, and
`:Sess unmark @s` removes it. Use `:Sess load @s` or the optional native
`<C-q>{mark}` mapping to navigate. Setting a mark and navigating a mark are
separate actions. Path targets beginning with `~/`, `/`, `./`, or `../` load their session or create one. Existing directories are resolved with `fs_realpath`, so symlinked paths share one session identity. Invalid or missing directories are rejected. Creating a session opens the default file explorer in the project root.

In the Telescope session picker, a path prompt switches to immediate directory completion. `<Tab>` inserts the selected directory and a trailing slash while keeping the picker open. `<Enter>` loads or creates its session. Returning to a non-path prompt restores the normal session finder.

Deleted sessions are soft-deleted into the private `trash/` directory and remain recoverable while their metadata is valid. Corrupt records are reported and skipped. Restore refuses duplicate ids, names, or project paths.

## Persistence and safety

`:checkhealth sess` checks setup, storage access, corrupt/version-incompatible metadata and missing snapshots. It never sources snapshots, writes probes or repairs/deletes data.

## Development

```sh
sh tests/run.sh
NVIM_BIN=/path/to/latest-stable/nvim sh tests/run.sh
```

Tests run in fresh Neovim processes with temporary HOME/XDG/storage/fixtures, cleaned up on exit. User config, plugins, ShaDa and swap files are disabled. Telescope isn't required. CI tests latest stable only.

Format changed Lua files with `stylua path/to/file.lua`; `.stylua.toml` defines the shared style. Use `stylua --check path/to/file.lua` to check without modifying files.
