# sessions.nvim

A simple plugin for managing sessions in Neovim.

https://github.com/user-attachments/assets/069c4d03-4140-4e02-8678-20eef0cbc923

## Features

- Save and load sessions
- Pin sessions
- Delete sessions
- Rename sessions
- List sessions (with telescope.nvim)

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
    attach_after_enter = true, -- if false just change cwd
    promt_title = "Your title"
}

M.keys = {
    { "<leader>ss", "<cmd>Sessions save<cr>", desc = "Save session" },
    { "<leader>sc", "<cmd>Sessions pin<cr>", desc = "Pin session" },
    { "<leader>sa", "<cmd>Sessions attach<cr>", desc = "Attach session" },
    { "<leader>sl", "<cmd>Sessions list<cr>", desc = "List sessions" }, -- only if you have telescope.nvim
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
    attach_after_enter = true, -- if false just change cwd
    promt_title = "Your title"
})

vim.keymap.set("n", "<leader>ss", "<cmd>Sessions save<cr>", { desc = "Save session" })
vim.keymap.set("n", "<leader>sc", "<cmd>Sessions pin<cr>", { desc = "Pin session" })
vim.keymap.set("n", "<leader>sa", "<cmd>Sessions attach<cr>", { desc = "Attach session" })
vim.keymap.set("n", "<leader>sl", "<cmd>Sessions list<cr>", { desc = "List sessions" }) -- only if you have telescope.nvim
```

</details>

## Add your own functionality

Auto save session on exit and auto attach session on enter (you need to delete M.opts and use only M.config):

```lua
M.lazy = false -- REQUIRED

M.config = function()
    ---@class Builtins
    ---@field attach fun(session: Session | nil): boolean
    ---@field completion fun(): string[]
    ---@field get_current fun(): Session
    ---@field open_list fun()
    ---@field pin fun()
    ---@field save fun(): boolean
    ---@field setup fun(user_opts: table): Builtins
    local builtins = require("sessions.nvim").setup()

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

Or you can move between previous session with \<leader\>\<C-^\>:

```lua
M.config = function()
    ---@class Session
    ---@field name string | nil
    ---@field path string | nil

    ---@type Session
    local prev = { name = "", path = "" }

    ---@class Builtins
    ---@field attach fun(session: Session | nil): boolean
    ---@field completion fun(): string[]
    ---@field get_current fun(): Session
    ---@field open_list fun()
    ---@field pin fun()
    ---@field save fun(): boolean
    ---@field setup fun()
    local builtins = require("sessions.nvim").setup()

    ---@param new_session Session
    local goto_prev = function(new_session)
        prev = builtins.get_current()
        if new_session.path ~= "" and prev.path ~= new_session.path then
            builtins.attach({ path = new_session.path })
        end
    end

    vim.keymap.set("n", "<leader><C-^>", function()
        builtins.save()
        vim.cmd("wa")
        vim.cmd("silent! bufdo bd")
        goto_prev(prev)
    end)

    vim.api.nvim_create_user_command("CustomSessionAttach", function(input)
        prev = builtins.get_current()
        vim.cmd("Sessions attach " .. input.args)
    end, {
        nargs = "?",
        complete = builtins.completion
    })
end

M.keys {
    -- ...
    { "<leader>sa", "<cmd>CustomSessionAttach<cr>", desc = "Attach session" }
}
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
