local commands = require("sessionizer.commands")
local session = require("sessionizer.session")

local subcommands = {
    list = commands.list,
    save = commands.save,
    pin = function(session_name)
        local s = nil
        if session_name and session_name ~= "" then
            s = session.get.by_name(session_name)
        else
            s = session.get.current()
        end
        if s then
            commands.pin(s)
        end
    end,
    load = function(session_name)
        if session_name then
            local s = nil
            if session_name and session_name ~= "" then
                s = session.get.by_name(session_name)
            else
                s = session.get.current()
            end
            if s then
                commands.load(s)
            end
        end
    end,
    delete = function(session_name)
        local s = nil
        if session_name and session_name ~= "" then
            s = session.get.by_name(session_name)
        else
            s = session.get.current()
        end
        if s then
            commands.delete(s)
        end
    end,
    last = commands.last,
}

local function command_exists(cmd)
    for _, value in pairs({ "load", "delete", "pin" }) do
        if string.find(cmd, "Sess%s+" .. value) then
            return true
        end
    end
    return false
end

---@return fun(arglead: string, cmdline: string, cursorpos: number): string[]
local function generate_completion()
    return function(arglead, cmdline, _)
        if command_exists(cmdline) then
            local sessions = session.get.all()
            local sessions_names = {}
            for _, s in pairs(sessions) do
                table.insert(sessions_names, s.name)
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

vim.api.nvim_create_user_command("Sess", function(args)
        local cmd = args.fargs[1]
        local logger = require("sessionizer.logger")
        if subcommands[cmd] then
            subcommands[cmd](args.fargs[2])
        else
            logger.error("Unknown subcommand: " .. tostring(cmd))
        end
    end,
    {
        nargs = "*",
        complete = function(arglead, cmdline, cursorpos)
            local completion_fn = generate_completion()
            return completion_fn(arglead, cmdline, cursorpos)
        end
    }
)
