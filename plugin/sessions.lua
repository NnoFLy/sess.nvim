local commands = require("sessions.commands")
local utils = require("sessions.utils")

local subcommands = {
    list = commands.open_list,
    save = commands.save_session,
    pin = commands.pin_session,
    attach = function(args)
        local session_name = args.fargs[2]
        if session_name and #session_name > 0 then
            local ok = commands.attach_session({ name = session_name })
            if not ok then
                vim.notify("Session doesn't exist: " .. session_name, vim.log.levels.ERROR)
            end
        else
            local ok = commands.attach_session()
            if not ok then
                vim.notify("Cann't found session here", vim.log.levels.ERROR)
            end
        end
    end
}

vim.api.nvim_create_user_command("Sessions", function(args)
        local cmd = args.fargs[1]
        if subcommands[cmd] then
            subcommands[cmd](args)
        else
            vim.notify("Unknown subcommand: " .. tostring(cmd), vim.log.levels.ERROR)
        end
    end,
    {
        nargs = "*",
        complete = function(arglead, cmdline, cursorpos)
            local opts = require("sessions").get_opts()
            local completion_fn = utils.generate_completion(vim.tbl_keys(subcommands), opts.path, opts._marker)
            return completion_fn(arglead, cmdline, cursorpos)
        end
    }
)
