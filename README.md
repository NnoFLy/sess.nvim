# sessions.nvim

A simple plugin for managing sessions in Neovim.

https://github.com/user-attachments/assets/069c4d03-4140-4e02-8678-20eef0cbc923

## Features

- Save and load sessions
- Pin sessions
- Delete sessions
- Rename sessions
- Auto-completion sessions (AttachSession)
- List sessions (with telescope.nvim)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
local M = { "i0i-i0i/sessions.nvim" }

--- OPTIONAL (only for SessionsList) ---
M.dependencies = {
    "nvim-telescope/telescope.nvim",
    "nvim-lua/plenary.nvim"
}
--- OPTIONAL (only for SessionsList) ---

M.opts = {
    path = "path/to/sessions_folder", -- default = "~/sessions"
    attach_after_enter = true, -- if false just change cwd
    promt_title = "Your title"
}

M.keys = {
    { "<leader>ss", "<cmd>SessionSave<cr>", desc = "Save session" },
    { "<leader>sc", "<cmd>SessionPin<cr>", desc = "Pin session" },
    { "<leader>sa", "<cmd>SessionAttach<cr>", desc = "Attach session" },
    { "<leader>sl", "<cmd>SessionsList<cr>", desc = "List sessions" }, -- only if you have telescope.nvim
}

return M
```

## Default commands (You don't need to add this anywhere)

These are built-in functions, so this is how they work.

You can pin a new session, that means you give it a name, and it will appear in
completion menu (SessionAttach) or in SessionsList:

```lua
vim.api.nvim_create_user_command("SessionPin", function()
    sessions.pin_session()
end, {})
```

Show sessions list in telescope:

```lua
vim.api.nvim_create_user_command("SessionsList", function()
    sessions.open_list()
end, {})
```

This creates a session but doesn't assign a name to it, you can use SessionPin
to specify a name. Session is associated with current directory:

```lua
vim.api.nvim_create_user_command("SessionSave", function()
    sessions.save_session()
end, {})
```

Specify the session name and attach to it, if no name is specified this will try
to find a session for current path and than attach, if no session is found,
an error will be displayed:

```lua
local completion = require("sessions.utils").generate_completion(opts.path, opts._marker)
vim.api.nvim_create_user_command("SessionAttach", function(input)
    if input.args and #input.args > 0 then
        local args = input.args
        local ok = commands.attach_session({ name = args })
        if not ok then
            print("Session doesn't exist: " .. args)
        end
    else
        local ok = commands.attach_session()
        if not ok then
            print("Cann't found session here")
        end
    end
end, {
    nargs = "?",
    complete = completion
})
```

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
        vim.cmd("SessionAttach " .. input.args)
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
