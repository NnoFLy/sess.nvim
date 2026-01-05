local commands = require("sessionizer.commands")
local session = require("sessionizer.session")
local logger = require("sessionizer.logger")
local state = require("sessionizer.state")
local utils = require("sessionizer.utils")

local subcommands = {
    list = commands.list,
    save = commands.save,
    pin = function(session_name)
        local s = nil
        if session_name and session_name ~= "" then
            s = session.get.by_name(session_name)
        else
            if not commands.save() then
                logger.error("Cannot save session")
                return
            end
            s = state.get_current_session()
        end
        if not s then
            logger.error("Cannot get session for pinning")
            return
        end

        commands.pin(s)
    end,
    load = function(session_name)
        local s = nil
        if session_name and session_name ~= "" then
            s = session.get.by_name(session_name)
        else
            s = session.get.by_path(vim.fn.getcwd())
        end
        if not s then
            commands.create(session_name)
            return
        end

        commands.load(s)
    end,
    unload = commands.unload,
    delete = function(session_name)
        local s = nil
        if session_name and session_name ~= "" then
            s = session.get.by_name(session_name)
        else
            s = state.get_current_session()
        end

        if not s then
            logger.error("Cannot get session for deletion")
            return
        end

        commands.delete(s)
    end,
    last = commands.last,
}

local session_subs = { load = true, pin = true, delete = true }

local function keys(t)
    local out = {}
    for k in pairs(t) do table.insert(out, k) end
    table.sort(out)
    return out
end

local function filter_by_pattern(list, pattern)
    if not pattern or pattern == "" then
        return list
    end

    if not pattern:find("[%*%?]") then
        return vim.tbl_filter(function(item) return vim.startswith(item, pattern) end, list)
    end

    if pattern:sub(1,1) == "*" and pattern:sub(-1) ~= "*" then
        pattern = pattern .. "*"
    end

    local esc = pattern:gsub("([%^%$%(%)%%%.%+%-%[%]])", "%%%1")
    esc = esc:gsub("%*", ".*"):gsub("%?", ".")
    local lua_pat = "^" .. esc .. "$"

    return vim.tbl_filter(function(item) return item:match(lua_pat) end, list)
end

local function session_names()
    local sessions = utils.get_items() or {}
    local out = {}
    for _, s in pairs(sessions) do
        if s and s.name then table.insert(out, s.name) end
    end
    table.sort(out)
    return out
end

local function sess_complete(_, cmdline, cursorpos)
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

    local second_prefix = rest or ""

    if session_subs[first] then
        return filter_by_pattern(session_names(), second_prefix)
    end

    return filter_by_pattern(keys(subcommands), first)
end


vim.api.nvim_create_user_command("Sess", function(args)
    local cmd = args.fargs[1]
    if subcommands[cmd] then
        subcommands[cmd](args.fargs[2])
    else
        logger.error("Unknown subcommand: " .. tostring(cmd))
    end
end, {
    nargs = "*",
    complete = sess_complete,
})
