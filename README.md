# sessions.nvim

A simple plugin for managing sessions in Neovim.

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
<summary>lazy.nvim (https://github.com/folke/lazy.nvim)</summary>

```lua
local M = { "i0i-i0i/sessions.nvim" }

--- OPTIONAL (only for 'Sessions list') ---
M.dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim"
}
--- OPTIONAL (only for 'Sessions list') ---

M.opts = {
    prompt_title = "🗃️ All sessions",
    before_load = {
        auto_save_files = false,
        auto_remove_buffers = false,
        custom = function() end,
    },
    after_load = {
        custom = function() end,
    }
}

M.keys = {
    { "<leader>ss", "<cmd>Sessions save<cr>", desc = "Save session" },
    { "<leader>sc", "<cmd>Sessions pin<cr>", desc = "Pin session" },
    { "<leader>sa", "<cmd>Sessions load<cr>", desc = "Load session" },
    { "<leader>sl", "<cmd>Sessions list<cr>", desc = "List sessions" }, -- only if you have telescope.nvim
    { "<leader><C-^>", "<cmd>Sessions last<cr>", desc = "Load the previous session" },
}

return M
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
require("sessions").setup({
    prompt_title = "🗃️ All sessions",
    before_load = {
        auto_save_files = false,
        auto_remove_buffers = false,
        custom = function() end,
    },
    after_load = {
        custom = function() end,
    }
})

vim.keymap.set("n", "<leader>ss", "<cmd>Sessions save<cr>", { desc = "Save session" })
vim.keymap.set("n", "<leader>sc", "<cmd>Sessions pin<cr>", { desc = "Pin session" })
vim.keymap.set("n", "<leader>sa", "<cmd>Sessions load<cr>", { desc = "Load session" })
vim.keymap.set("n", "<leader>sl", "<cmd>Sessions list<cr>", { desc = "List sessions" }) -- only if you have telescope.nvim
vim.keymap.set("n", "<leader><C-^>", "<cmd>Sessions last<cr>", { desc = "Load the previous session" })
```

</details>

## Usage

```lua
local commands = require("sessions.commands")
```

- Save current session

```lua
---@return boolean
commands.save()  -- or :Sessions save
```

- Pin current session and give it a name.
If 'session_name' is not provided, you will be prompted to enter a name

```lua
---@param session_name string | nil
---@return nil
commands.pin("session_name")  -- or :Sessions pin
```

- Load the session (if 'session_name' is not provided, load the session bases on cwd)

```lua
---@class BeforeLoadOpts
---@field auto_save_files boolean | nil
---@field auto_remove_buffers boolean | nil
---@field custom function | nil

---@class AfterLoadOpts
---@field custom function | nil

---@param session_name string | nil
---@param before_load_opts BeforeLoadOpts | nil
---@param after_load_opts AfterLoadOpts | nil
---@return boolean
commands.load("session_name", {}, {})  -- or :Sessions load [<session_name>]
```

- Telescope list sessions

```lua
---@param prompt_title string | nil
---@return nil
commands.list("All sessions")  -- or :Sessions list
```

- Delete session (if 'session_name' is not provided, delete current session)

```lua
---@param session_name string | nil
---@return nil
commands.delete("session_name")  -- or :Sessions delete [<session_name>]
```

- Rename session (if 'session_name' is not provided, rename current session)
If 'new_session_name' is not provided, you will be prompted to enter a new name

```lua
---@param session_name string | nil
---@param new_session_name string | nil
---@return nil
commands.rename("session_name", "new_name")  -- or :Sessions rename [<session_name>]
```

- Load the previous session

```lua
---@param auto_save_files boolean | nil
---@return nil
commands.last(true)  -- or :Sessions last
```

- Get current session

```lua
---@return Session
commands.get.current()
```

- Get all sessions

```lua
---@return Session[]
commands.get.all()
```

- Get session by name

```lua
---@param name string
---@return Session | nil
commands.get.by_name(name)
```

## Auto session

Auto save session on exit and auto load session on enter (you need to delete M.opts and use only M.config):
If you open a file, then session won't be loaded, but if you run neovim like 'nvim', then it will be loaded.

```lua
M.lazy = false -- REQUIRED

M.config = function()
    require("sessions").setup({})

    local commands = require("sessions.commands")

    vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
            vim.schedule(function()
                if vim.fn.argc() == 0 then
                    commands.load()
                end
            end)
        end,
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            local utils = require("sessions.utils")
            if utils.contains(vim.bo.filetype,
                    { "gitcommit" }) then
                return
            end
            commands.save()
        end
    })
end
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

1. Sort by last used
2. Save before switching
3. Remote sessions
4. Show current session
5. Make it better
