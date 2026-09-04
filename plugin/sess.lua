local commands = require("sess.commands")
local session = require("sess.session")
local log = require("sess.log")
local state = require("sess.state")

local subcommands = {
    list = commands.list,
    save = commands.save,
    create = function(path)
        path = path and path ~= "" and path or vim.fn.getcwd()
        path = vim.fs.normalize(path)

        local s = session.get_by_path(path)
        if s then
            commands.load(s)
            return
        end

        commands.create(path)
    end,
    pin = function(session_name)
        local s
        if session_name and session_name ~= "" then
            s = session.get_by_name(session_name)
        else
            if not commands.save() then
                return
            end
            s = state.get_current_session()
        end

        if not s then
            log.error("Cannot get session for pinning")
            return
        end

        commands.pin(s)
    end,
    rename = function(session_name)
        local s
        if session_name and session_name ~= "" then
            s = session.get_by_name(session_name)
        else
            s = state.get_current_session()
        end

        if not s then
            log.error("Cannot get session for renaming")
            return
        end

        commands.rename(s)
    end,
    load = function(session_name_or_path)
        local s
        if session_name_or_path and session_name_or_path ~= "" then
            s = session.get_by_name(session_name_or_path)
            if not s then
                local path = vim.fs.normalize(session_name_or_path)
                if vim.fn.isdirectory(path) == 1 then
                    s = session.get_by_path(path)
                end
            end
        else
            s = session.get_by_path(vim.fn.getcwd())
        end

        if not s then
            if session_name_or_path and session_name_or_path ~= "" then
                log.error("Session not found: " .. session_name_or_path)
            else
                commands.create(vim.fn.getcwd())
            end
            return
        end

        commands.load(s)
    end,
    unload = commands.unload,
    delete = function(session_name)
        local s
        if session_name and session_name ~= "" then
            s = session.get_by_name(session_name)
        else
            s = state.get_current_session()
        end

        if not s then
            log.error("Cannot get session for deletion")
            return
        end

        commands.delete(s)
    end,
    last = commands.last,
}

local session_subcommands_with_args = {
    load = true,
    pin = true,
    rename = true,
    delete = true,
}

local function keys(t)
    local out = {}
    for k in pairs(t) do
        table.insert(out, k)
    end
    table.sort(out)
    return out
end

local function filter_by_pattern(list, pattern)
    if not pattern or pattern == "" then
        return list
    end

    if not pattern:find("[%*%?]") then
        return vim.tbl_filter(function(item)
            return vim.startswith(item, pattern)
        end, list)
    end

    if pattern:sub(1, 1) == "*" and pattern:sub(-1) ~= "*" then
        pattern = pattern .. "*"
    end

    local esc = pattern:gsub("([%^%$%(%)%%%.%+%-%[%]])", "%%%1")
    esc = esc:gsub("%*", ".*"):gsub("%?", ".")
    local lua_pat = "^" .. esc .. "$"

    return vim.tbl_filter(function(item)
        return item:match(lua_pat)
    end, list)
end

local function session_names()
    local sessions = session.list() or {}
    local out = {}
    for _, s in ipairs(sessions) do
        table.insert(out, s.metadata.name)
    end
    table.sort(out)
    return out
end

local function path_dirs(arg_lead)
    local ok, matches = pcall(vim.fn.getcompletion, arg_lead or "", "dir")
    if not ok or type(matches) ~= "table" then
        return {}
    end
    return matches
end

local function sess_complete(arg_lead, cmdline, cursorpos)
    local before = cmdline:sub(1, cursorpos)
    local tail = before:gsub("^%s*:?%s*Sess%s*", "")

    if tail == "" then
        return keys(subcommands)
    end

    local first, rest = tail:match("^(%S+)%s*(.*)$")
    if not first then
        return filter_by_pattern(keys(subcommands), tail)
    end

    if not tail:match("%s") then
        return filter_by_pattern(keys(subcommands), first)
    end

    if session_subcommands_with_args[first] then
        return filter_by_pattern(session_names(), rest or "")
    end

    if first == "create" then
        return path_dirs(arg_lead)
    end

    return {}
end

vim.api.nvim_create_user_command("Sess", function(args)
    if #args.fargs > 2 then
        log.error("Too many arguments: expected at most a subcommand and one argument")
        return
    end

    local cmd = args.fargs[1]
    if not cmd or cmd == "" then
        log.error("Missing subcommand; use :Sess <Tab> to see available commands")
        return
    end

    if subcommands[cmd] then
        subcommands[cmd](args.fargs[2])
        return
    end

    log.error("Unknown subcommand: " .. tostring(cmd))
end, {
    nargs = "*",
    complete = sess_complete,
})
