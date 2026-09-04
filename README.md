# Sess.nvim

Plugin for managing sessions in Neovim.

## Features

- Save and load sessions
- Pin sessions
- Delete sessions
- Rename sessions
- List sessions (with telescope.nvim)
- Switch to last session

## Installation

<details>
<summary>lazy.nvim</summary>

```lua
return {
    "i0i-i0i/sess.nvim",
    lazy = false,

--- OPTIONAL (only for 'Sess list') ---
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-telescope/telescope.nvim",
    },
--- OPTIONAL (only for 'Sess list') ---
}
```

</details>

<details>
<summary>Native (with vim.pack)</summary>

```lua
--- OPTIONAL (only for 'Sess list') ---
vim.pack.add({ "https://github.com/nvim-lua/plenary.nvim" })
vim.pack.add({ "https://github.com/nvim-telescope/telescope.nvim" })
--- OPTIONAL (only for 'Sess list') ---

vim.pack.add({ "https://github.com/i0i-i0i/sess.nvim" })
```

</details>

## Config

Default config:

```lua
require("sess").setup({
    paths = {
        "path/to/your/projects/*",  -- will add all folders in this path to the sessions list
        "path/to/your/project",  -- will add this folder to the sessions list
    },
    smart_auto_load = true,  -- smart auto load session on enter to neovim
                             -- if you open a file (like 'nvim file.txt' or 'nvim .'),
                             -- then session won't be loaded,
                             -- but if you run neovim like 'nvim', then it will be loaded
    auto_save = true,  -- auto save session on exit from neovim
                       -- works only if session is loaded
    exclude_filetypes = { "gitcommit" },  -- exclude from auto save
    log_level = "info", -- debug|info|warn|error
    store_path = vim.fn.stdpath("data") .. "/sess.nvim",
    before_load = {
        auto_save_files = false,     -- auto save files before switch to another session
        auto_hide_buffers = true,  -- auto remove buffers before switch to another session
        custom = function() end,
    },
    after_load = {
        custom = function() end
    },
    on_unload = { -- runs after session is unloaded or deleted (Sess delete|unload)
        custom = function() end
    }
})
```

## Usage

Example keybindings:

```lua
vim.keymap.set("n", "<M-s>s", "<cmd>Sess save<cr>", { desc = "Save session" })
vim.keymap.set("n", "<M-s>p", "<cmd>Sess pin<cr>", { desc = "Pin session" })
vim.keymap.set("n", "<M-s>c", ":Sess create ", { desc = "Create session" })
vim.keymap.set("n", "<M-s>l", "<cmd>Sess load<cr>", { desc = "Load session" })
vim.keymap.set("n", "<M-s>u", "<cmd>Sess unload<cr>", { desc = "Unload session" })
vim.keymap.set("n", "<C-s>", "<cmd>Sess list<cr>", { desc = "List sessions" }) -- only if you have telescope.nvim
vim.keymap.set("n", "<leader><C-^>", "<cmd>Sess last<cr>", { desc = "Load the previous session" })
```

Command completion:

- `:Sess <Tab>` completes subcommands.
- `:Sess load|pin|rename|delete <Tab>` completes session names.
- `:Sess create <Tab>` completes directories.

## Status line

Show current session in statusline:

```lua
local statusline = vim.o.statusline

require("sess").setup({
    ...
    log_level = "error",
    after_load = {
        custom = function()
            local session = vim.g.sess_current_session or ""
            if session ~= "" then
                session = "[" .. session .. "] "
            end
            vim.o.statusline = session .. statusline
        end
    },
    on_unload = {
        custom = function()
            vim.o.statusline = statusline
        end
    }
})
```

## Telescope

```lua
require("telescope").load_extension("sess")
```

### Default config

```lua
local sess_actions = require("telescope._extensions.sess.actions")

require("telescope").setup({
    extensions = {
        -- Defaults:
        sess = {
            prompt_title = "🗃️ All sessions",
            mappings = {
                ["i"] = {
                    ["<C-d>"] = sess_actions.delete_session,
                    ["<C-r>"] = sess_actions.rename_session,
                    ["<CR>"] = sess_actions.enter,
                },
                ["n"] = {
                    ["dd"] = sess_actions.delete_session,
                    ["rr"] = sess_actions.rename_session,
                    ["<CR>"] = sess_actions.enter,
                },
            },
        }
    }
})

```

## Troubleshooting

<details>
<summary>If you set `before_load.auto_save_files = true` and you use conform.nvim</summary>

```lua
require("conform").setup({
    formatters_by_ft = { ... },

    -- Remove format_after_save
    format_after_save = { lsp_format = "fallback", timeout_ms = 500, async = true },

    -- use format_on_save instead
    format_on_save = { timeout_ms = 500, lsp_format = "fallback" },
})
```

Or just set `before_load.auto_save_files = false`

</details>

## TODO

- [ ] Move by directories with Telescope ('~', '/', './', '../')
- [ ] Open remote session from Telescope ('/ssh:<login>/')
- [ ] Remote sessions (with `ssh`)
- [ ] Keymaps for remote session, via callback
- [ ] sshfs
