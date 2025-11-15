local commands = require("sessions.commands")
local utils = require("sessions.utils")

local subcommands = {
    list = commands.list,
    save = commands.save,
    pin = commands.pin,
    attach = commands.attach,
    last = commands.last,
    rename = commands.rename,
    delete = commands.delete
}

local function command_exists(cmd)
    for _, value in pairs({ "attach", "rename", "delete" }) do
        if string.find(cmd, "Sessions%s+" .. value) then
            return true
        end
    end
    return false
end

---@param path string
---@param marker string
---@return fun(arglead: string, cmdline: string, cursorpos: number): string[]
local function generate_completion(path, marker)
    return function(arglead, cmdline, _)
        if command_exists(cmdline) then
            local sessions = utils.get_sessions(path, marker)
            local sessions_names = {}
            for _, session in pairs(sessions) do
                table.insert(sessions_names, session.name)
            end
            return vim.tbl_filter(function(name)
                return vim.startswith(name, arglead)
            end, sessions_names)
        end

        return vim.tbl_filter(function(name)
            return vim.startswith(name, arglead)
        end, vim.tbl_keys(subcommands))
    end
end

vim.api.nvim_create_user_command("Sessions", function(args)
        local cmd = args.fargs[1]
        if subcommands[cmd] then
            subcommands[cmd](args.fargs[2])
        else
            vim.notify("Unknown subcommand: " .. tostring(cmd), vim.log.levels.ERROR)
        end
    end,
    {
        nargs = "*",
        complete = function(arglead, cmdline, cursorpos)
            local opts = require("sessions").get_opts()
            local completion_fn = generate_completion(opts.path, opts._marker)
            return completion_fn(arglead, cmdline, cursorpos)
        end
    }
)
