# sessionizer.nvim

Plugin for managing sessions in Neovim, like tmux-sessionizer.

## Features

- Save and load sessions
- Pin sessions
- Delete sessions
- Rename sessions
- List sessions (with telescope.nvim)
- Switch to last session
- Handle terminals

## Installation

<details>
<summary>lazy.nvim</summary>

```lua
return {
    "i0i-i0i/sessionizer.nvim",
    lazy = false,

--- OPTIONAL (only for 'Sess list') ---
    dependencies = {
        "nvim-telescope/telescope.nvim",
        "nvim-lua/plenary.nvim"
    },
--- OPTIONAL (only for 'Sess list') ---
}
```

</details>

<details>
<summary>Native (with vim.pack)</summary>

```lua
--- OPTIONAL (only for 'Sess list') ---
vim.pack.add({ "https://github.com/nvim-telescope/telescope.nvim" })
vim.pack.add({ "https://github.com/nvim-lua/plenary.nvim" })
--- OPTIONAL (only for 'Sess list') ---

vim.pack.add({ "https://github.com/i0i-i0i/sessionizer.nvim" })
```

</details>

## Config

Default config:

```lua
require("sessionizer").setup({
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
    before_load = {
        auto_save_files = false,  -- auto save files before switch to another session
        auto_remove_buffers = false,  -- auto remove buffers before switch to another session
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
vim.keymap.set("n", "<leader>ss", "<cmd>Sess save<cr>", { desc = "Save session" })
vim.keymap.set("n", "<leader>sc", "<cmd>Sess pin<cr>", { desc = "Pin session" })
vim.keymap.set("n", "<leader>sa", "<cmd>Sess load<cr>", { desc = "Load session" })
vim.keymap.set("n", "<leader>su", "<cmd>Sess unload<cr>", { desc = "Unload session" })
vim.keymap.set("n", "<leader>sl", "<cmd>Sess list<cr>", { desc = "List sessions" }) -- only if you have telescope.nvim
vim.keymap.set("n", "<leader><C-^>", "<cmd>Sess last<cr>", { desc = "Load the previous session" })
```

## Status line

Show current session in statusline:

```lua
local statusline = vim.o.statusline

require("sessionizer").setup({
    ...
    log_level = "error",
    after_load = {
        custom = function()
            local session = vim.g.sessionizer_current_session or ""
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
require("telescope").load_extension("sessionizer")
```

### Default config

```lua
local sessionizer_actions = require("telescope._extensions.sessionizer.actions")

require("telescope").setup({
    extensions = {
        -- Defaults:
        sessionizer = {
            prompt_title = "🗃️ All sessions",
            mappings = {
                ["i"] = {
                    ["<C-d>"] = sessionizer_actions.delete_session,
                    ["<C-r>"] = sessionizer_actions.rename_session,
                    ["<CR>"] = sessionizer_actions.enter,
                },
                ["n"] = {
                    ["dd"] = sessionizer_actions.delete_session,
                    ["rr"] = sessionizer_actions.rename_session,
                    ["<CR>"] = sessionizer_actions.enter,
                },
            },
        }
    }
})

```

## Troubleshooting

<details>
<summary>If you set 'before_load.auto_save_files = true' and you use conform.nvim</summary>

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

## TODOs

- [ ] Remote sessions
