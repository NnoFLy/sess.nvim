local commands = require("sessions.commands")

local subcommands = {
    list = commands.list,
    save = commands.save,
    pin = commands.pin,
    load = commands.load,
    last = commands.last,
    rename = commands.rename,
    delete = commands.delete
}

local function command_exists(cmd)
    for _, value in pairs({ "load", "rename", "delete" }) do
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
            local sessions = commands.get.all(path, marker)
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
        local utils = require("sessions.utils")
        if subcommands[cmd] then
            subcommands[cmd](args.fargs[2])
        else
            utils.notify("Unknown subcommand: " .. tostring(cmd), vim.log.levels.ERROR)
        end
    end,
    {
        nargs = "*",
        complete = function(arglead, cmdline, cursorpos)
            local consts = require("sessions.consts")
            local completion_fn = generate_completion(consts.path, consts.marker)
            return completion_fn(arglead, cmdline, cursorpos)
        end
    }
)
