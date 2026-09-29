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
```

## Usage

| Command | Behavior |
| --- | --- |
| `:Sess create [path]` | Create a session, or load the existing one for that path |
| `:Sess load [name/id/path]` | Switch sessions; defaults to current cwd |
| `:Sess save` | Save the current session |
| `:Sess last` | Return to the previous session |
| `:Sess unload [name/id/path]` | Close a session's buffers and terminal jobs; defaults to current |
| `:Sess pin [target]` | Toggle pin; defaults to current session |
| `:Sess rename [target] [name]` | Rename; prompts for a missing name |
| `:Sess delete [target]` | Move to private trash; defaults to current session |
| `:Sess restore [target]` | Restore from trash, or open the deleted-session picker |
| `:Sess list` | Open Telescope |

```lua
vim.keymap.set("n", "<M-s>s", "<cmd>Sess save<cr>")
vim.keymap.set("n", "<M-s>l", "<cmd>Sess list<cr>")
vim.keymap.set("n", "<leader><C-^>", "<cmd>Sess last<cr>")
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
    -- Operation succeeded, but metadata updates or observers reported errors.
end

api.session.save() -- current session only
api.session.unload("my-project") -- omit target for current; refuses unconfirmed edits/jobs
local current = api.state.current()
local previous = api.state.prev()
local active = api.state.active()
local ok, err, sessions, diagnostics = api.session.list()
local ok, err, deleted, diagnostics = api.session.list_deleted()
api.session.restore("name-or-id-or-trash-key")
```

Mutations return `(ok, err, session, diagnostics)`, with diagnostic strings on success. Loading the current session succeeds without saves, hooks or events. State getters return defensive copies.

Listing returns `false` for store-wide failures; corrupt records are skipped with diagnostics, never repaired or deleted automatically. Create/rename refuse to claim uniqueness with damaged metadata. `api.items.get_items()` returns `(items, err, diagnostics)`; UI adapters report diagnostics.

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

Events: `SessCreated`, `SessLoaded`, `SessSaved`, `SessUnloaded`, `SessDeleted`, `SessRestored`, `SessRenamed`, `SessPinned`.

State commits before `after_operation`, then the event fires. Outgoing saves emit `SessSaved` first. Create emits only `SessCreated`; switching doesn't emit `SessUnloaded`. Explicit unload does, as does current-session deletion before `SessDeleted`. Other deletions emit only `SessDeleted`.

Payloads are defensive `{ operation, session, current }` records; `current` may be nil. Hooks/events allow queries but reject recursive mutations. Post-hook/subscriber errors don't undo success. Subscriber execution follows Neovim's autocmd rules: Neovim may display errors, and those exposed through its API or `v:errmsg` become diagnostics.

## Telescope

Install telescope.nvim and plenary.nvim, then:

```lua
require("telescope").load_extension("sess")
```

Enter loads/creates. Ctrl-d (insert) or `dd` (normal) deletes with confirmation. `:Sess restore` opens a deleted-session picker; Enter restores the selected record. Restore completion accepts names, ids and trash keys. Restore only moves persisted data back and never loads or changes editor state. Commands, Telescope and autocommands use the same lifecycle.

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
