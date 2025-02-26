# sessions.nvim

A simple plugin for managing sessions in Neovim.

https://github.com/user-attachments/assets/069c4d03-4140-4e02-8678-20eef0cbc923

## Features

- Create and load sessions
- Delete sessions
- List sessions

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
local M = { "i0i-i0i/sessions.nvim" }

M.dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim"
}

M.config = function()
    require("sessions").setup({
        path = "path/to/sessions_folder", -- default = "~/sessions"
        attach_after_enter = true, -- if false just change cwd
        promt_title = "Your title"
    })
end

M.keys = {
    { "<leader>ss", "<cmd>SessionSave<cr>", desc = "Save session" },
    { "<leader>sc", "<cmd>SessionCreate<cr>", desc = "Create session" },
    { "<leader>sa", "<cmd>SessionAttach<cr>", desc = "Attach session" },
    { "<leader>sl", "<cmd>SessionsList<cr>", desc = "List sessions" },
}

return M
```

## Default commands

Create new session for current path:

```lua
vim.api.nvim_create_user_command("SessionCreate", function()
    sessions.create_session()
end, {})
```

Show sessions list in telescope:

```lua
vim.api.nvim_create_user_command("SessionsList", function()
    sessions.open_list()
end, {})
```

Save current session:

```lua
vim.api.nvim_create_user_command("SessionSave", function()
    sessions.save_session()
end, {})
```

Find session (in opts.path) for current path and attach, if not found print error:

```lua
vim.api.nvim_create_user_command("SessionAttach", function()
    local _, err = pcall(sessions.attach_session)
    if err then
        print("Cann't found session here")
    end
end, {})
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
