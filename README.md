# sessions.nvim

Plugin for managing sessions in Neovim, like tmux-sessionizer.

https://github.com/user-attachments/assets/069c4d03-4140-4e02-8678-20eef0cbc923

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
    "i0i-i0i/sessions.nvim",
    lazy = false,

--- OPTIONAL (only for 'Sessions list') ---
    dependencies = {
        "nvim-telescope/telescope.nvim",
        "nvim-lua/plenary.nvim"
    },
--- OPTIONAL (only for 'Sessions list') ---
}
```

</details>

<details>
<summary>Native (with vim.pack)</summary>

```lua
--- OPTIONAL (only for 'Sessions list') ---
vim.pack.add({ "https://github.com/nvim-telescope/telescope.nvim" })
vim.pack.add({ "https://github.com/nvim-lua/plenary.nvim" })
--- OPTIONAL (only for 'Sessions list') ---

vim.pack.add({ "https://github.com/i0i-i0i/sessions.nvim" })
```

</details>

## Config

Default config:

```lua
require("sessions").setup({
    paths = {
        "path/to/your/projects/*",  -- will add all folders in this path to the sessions list
        "path/to/your/project",  -- will add this folder to the sessions list
    },
    smart_auto_load = true,  -- smart auto load session on enter to neovim
                             -- if you open a file (like 'nvim file.txt' or 'nvim .'),
                             -- then session won't be loaded,
                             -- but if you run neovim like 'nvim', then it will be loaded
    auto_save = true,  -- auto save session on exit from neovim
    exclude_filetypes = { "gitcommit" },  -- exclude from auto save
    before_load = {
        auto_save_files = false,  -- auto save files before switch to another session
        auto_remove_buffers = false,  -- auto remove buffers before switch to another session
        custom = function() end,
    },
    after_load = {
        custom = function() end,
    }
})
```

## Usage

Example keybindings:

```lua
vim.keymap.set("n", "<leader>ss", "<cmd>Sessions save<cr>", { desc = "Save session" })
vim.keymap.set("n", "<leader>sc", "<cmd>Sessions pin<cr>", { desc = "Pin session" })
vim.keymap.set("n", "<leader>sa", "<cmd>Sessions load<cr>", { desc = "Load session" })
vim.keymap.set("n", "<leader>sl", "<cmd>Sessions list<cr>", { desc = "List sessions" }) -- only if you have telescope.nvim
vim.keymap.set("n", "<leader><C-^>", "<cmd>Sessions last<cr>", { desc = "Load the previous session" })
```

## API

```lua
local commands = require("sessions.api").commands
local get = require("sessions.api").get
```

### Commands

- Save current session.

```lua
---@return boolean
commands.save()  -- or :Sessions save
```

- Pin and give session a name.
    - If 's' is not provided, get current session.
    - If 'new_name' is not provided, you will be prompted to enter a new name.

```lua
---@param s Session | nil
---@param new_name string | nil
---@return nil
commands.pin(<session>)  -- or :Sessions pin
```

- Load the session.
    - If 's' is not provided, load the session bases on cwd.

```lua
---@class BeforeLoadOpts
---@field auto_save_files boolean | nil
---@field auto_remove_buffers boolean | nil
---@field custom function | nil

---@class AfterLoadOpts
---@field custom function | nil

---@param s Session | nil
---@param before_load_opts BeforeLoadOpts | nil
---@param after_load_opts AfterLoadOpts | nil
---@return boolean
commands.load(<session>, <before_load_opts>, <after_load_opts>)  -- or :Sessions load [<session_name>]
```

- Telescope list sessions

```lua
---@param prompt_title string | nil
---@return nil
commands.list("Title")  -- or :Sessions list
```

- Delete session (if 'session_name' is not provided, delete current session)
    - If 's' is not provided, delete current session.

```lua
---@param s Session | nil
---@return nil
commands.delete(<session>)  -- or :Sessions delete [<session_name>]
```

- Load the previous session

```lua
---@class BeforeLoadOpts
---@field auto_save_files boolean | nil
---@field auto_remove_buffers boolean | nil
---@field custom function | nil

---@class AfterLoadOpts
---@field custom function | nil

---@param load_opts BeforeLoadOpts | nil
---@param after_load_opts AfterLoadOpts | nil
---@return boolean
commands.last(<before_load_opts>, <after_load_opts>)  -- or :Sessions last
```

### Get

- Get current session

```lua
---@return Session
get.current()
```

- Get all sessions

```lua
---@return Session[]
get.all()
```

- Get session by name

```lua
---@param name string
---@return Session | nil
get.by_name(<name>)
```

- Get by path

```lua
---@param path string
---@return Session | nil
get.by_path(<path>)
```

## Telescope maps

```lua
{
    ["n"] = {
        ["dd"] = delete_session,
        ["rr"] = rename_session,
        ["<CR>"] = load_session,
    },
    ["i"] = {
        ["<C-d>"] = delete_session,
        ["<C-r>"] = rename_session,
        ["<CR>"] = load_session,
    }
}
```

## Troubleshooting

<details>
<summary>If you set 'auto_save_files = true' and you use conform.nvim</summary>

```lua
require("conform").setup({
    formatters_by_ft = { ... },

    -- Remove format_after_save
    format_after_save = { lsp_format = "fallback", timeout_ms = 500, async = true },

    -- use format_on_save instead
    format_on_save = { timeout_ms = 500, lsp_format = "fallback" },
})
```

Or just set `auto_save_files = false`

</details>

## TODOs

- [ ] Remote sessions
- [ ] Show current session
- [ ] Make it better
