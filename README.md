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
    path = "path/to/sessions_folder", -- default = "~/sessions"
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
    path = "path/to/sessions_folder", -- default = "~/sessions"
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
-- Save session
---@return boolean
require("sessions").save()  -- or :Sessions save

-- Pin session
require("sessions").pin()  -- or :Sessions pin

-- Attach session
---@param session_name string | nil
---@return boolean
require("sessions").attach()  -- or :Sessions attach [<arg>]

-- List sessions
require("sessions").list()  -- or :Sessions list

-- Delete session
---@param session_name string | nil
---@return nil
require("sessions").delete()  -- or :Sessions delete [<arg>]

-- Rename session
---@param session_name string | nil
---@return nil
require("sessions").rename()  -- or :Sessions rename [<arg>]

-- Attach to previous session
require("sessions").last()  -- or :Sessions last
```


## Auto session

Auto save session on exit and auto attach session on enter (you need to delete M.opts and use only M.config):

```lua
M.lazy = false -- REQUIRED

M.config = function()
    local builtins = require("sessions").setup()

    vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
            vim.schedule(function()
                builtins.attach()
            end)
        end
    })

    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            builtins.save()
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
