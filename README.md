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
    promt_title = "Your title"
}

M.keys = {
    { "<leader>ss", "<cmd>Sessions save<cr>", desc = "Save session" },
    { "<leader>sc", "<cmd>Sessions pin<cr>", desc = "Pin session" },
    { "<leader>sa", "<cmd>Sessions attach<cr>", desc = "Attach session" },
    { "<leader>sl", "<cmd>Sessions list<cr>", desc = "List sessions" }, -- only if you have telescope.nvim
    { "<leader><C-^>", "<cmd>Sessions last<cr>", desc = "Attach to previous session" },
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
    promt_title = "Your title"
})

vim.keymap.set("n", "<leader>ss", "<cmd>Sessions save<cr>", { desc = "Save session" })
vim.keymap.set("n", "<leader>sc", "<cmd>Sessions pin<cr>", { desc = "Pin session" })
vim.keymap.set("n", "<leader>sa", "<cmd>Sessions attach<cr>", { desc = "Attach session" })
vim.keymap.set("n", "<leader>sl", "<cmd>Sessions list<cr>", { desc = "List sessions" }) -- only if you have telescope.nvim
vim.keymap.set("n", "<leader><C-^>", "<cmd>Sessions last<cr>", { desc = "Attach to previous session" })
```

</details>

## Usage

```lua
local commands = require("sessions.commands")

-- Save session
---@return boolean
commands.save()  -- or :Sessions save

-- Pin session current session
---@param session_name string | nil
---@return nil
commands.pin("session_name")  -- or :Sessions pin

-- Attach to session (if 'session_name' is not provided, attach to session bases on cwd)
---@param session_name string | nil
---@return boolean
commands.attach("session_name")  -- or :Sessions attach [<arg>]

-- Telescope list sessions
---@param prompt_title string | nil
---@return nil
commands.list("All sessions")  -- or :Sessions list

-- Delete session (if 'session_name' is not provided, delete current session)
---@param session_name string | nil
---@return nil
commands.delete("session_name")  -- or :Sessions delete [<arg>]

-- Rename session (if 'session_name' is not provided, rename current session)
---@param session_name string | nil
---@param new_session_name string | nil
---@return nil
commands.rename("session_name", "new_name")  -- or :Sessions rename [<arg>]

-- Attach to previous session
---@return nil
commands.last()  -- or :Sessions last
```


## Auto session

Auto save session on exit and auto attach session on enter (you need to delete M.opts and use only M.config):

```lua
M.lazy = false -- REQUIRED

M.config = function()
    require("sessions").setup({})

    local commands = require("sessions.commands")

    vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
            vim.schedule(function()
                commands.attach()
            end)
        end
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
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
        ["<CR>"] = attach_session,
    },
    ["i"] = {
        ["<C-d>"] = delete_session,
        ["<C-r>"] = rename_session,
        ["<CR>"] = attach_session,
    }
}
```

## TODOs

1. Make it better
