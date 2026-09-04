local api = require("sess.api")
local log = require("sess.log")
local commands = require("sess.ui.commands")

local M = {}

local specs = {
    create = { handler = commands.create, max_args = 1, completion = "path" },
    delete = { handler = commands.delete, max_args = 1, completion = "session" },
    last = { handler = commands.last, max_args = 0 },
    list = { handler = commands.list, max_args = 0 },
    load = { handler = commands.load, max_args = 1, completion = "session" },
    pin = { handler = commands.pin, max_args = 1, completion = "session" },
    rename = { handler = commands.rename, max_args = 2, completion = { kind = "session", arg = 1 } },
    save = { handler = commands.save, max_args = 1 },
    unload = { handler = commands.unload, max_args = 0 },
}

local function keys(t)
    local result = {}
    for key in pairs(t) do
        result[#result + 1] = key
    end
    table.sort(result)
    return result
end

local function filter_by_pattern(list, pattern)
    pattern = pattern or ""
    if pattern == "" then
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

    local escaped = pattern:gsub("([%^%$%(%)%%%.%+%-%[%]])", "%%%1")
    escaped = escaped:gsub("%*", ".*"):gsub("%?", ".")
    local lua_pattern = "^" .. escaped .. "$"

    return vim.tbl_filter(function(item)
        return item:match(lua_pattern) ~= nil
    end, list)
end

local function session_names()
    if not api.opts.is_setup() then
        return {}
    end

    local ok, _, sessions = api.session.list()
    if not ok then
        return {}
    end

    local names = {}
    for _, item in ipairs(sessions or {}) do
        names[#names + 1] = item.metadata.name
    end
    table.sort(names)
    return names
end

local function path_dirs(arg_lead)
    local ok, matches = pcall(vim.fn.getcompletion, arg_lead or "", "dir")
    return ok and type(matches) == "table" and matches or {}
end

local function complete(arg_lead, cmdline, cursorpos)
    local tail = cmdline:sub(1, cursorpos):gsub("^%s*:?%s*Sess%s*", "")
    if tail == "" then
        return keys(specs)
    end

    local command, rest = tail:match("^(%S+)%s*(.*)$")
    if not command then
        return filter_by_pattern(keys(specs), tail)
    end

    if not tail:match("%s") then
        return filter_by_pattern(keys(specs), command)
    end

    local spec = specs[command]
    if not spec then
        return {}
    end

    local completion_kind = type(spec.completion) == "table" and spec.completion.kind or spec.completion
    local completion_arg = type(spec.completion) == "table" and spec.completion.arg or 1
    if completion_kind == "session" then
        local completed_args = {}
        for argument in rest:gmatch("%S+") do
            completed_args[#completed_args + 1] = argument
        end
        if #completed_args < completion_arg then
            return filter_by_pattern(session_names(), rest)
        end
        return {}
    end

    if spec.completion == "path" then
        return path_dirs(arg_lead)
    end

    return {}
end

---@class Sess.CommandContext
---@field args string[]
---@field bang boolean
---@field range_start integer
---@field range_end integer
---@field line1 integer
---@field line2 integer
---@field count integer
local function context(args)
    return {
        args = vim.list_slice(args.fargs, 2),
        bang = args.bang,
        range_start = args.line1,
        range_end = args.line2,
        line1 = args.line1,
        line2 = args.line2,
        count = args.line2 - args.line1 + 1,
    }
end

---@param args table
---@return boolean
function M.execute(args)
    local command = args.fargs[1]
    if not command or command == "" then
        log.error("Missing subcommand; use :Sess <Tab> to see available commands")
        return false
    end

    local spec = specs[command]
    if not spec then
        log.error("Unknown subcommand: " .. command)
        return false
    end

    local command_args = vim.list_slice(args.fargs, 2)
    if #command_args > spec.max_args then
        log.error(("Too many arguments for %s: expected at most %d argument%s"):format(
            command,
            spec.max_args,
            spec.max_args == 1 and "" or "s"
        ))
        return false
    end

    if not api.opts.is_setup() then
        log.error("sess.nvim is not configured; call require(\"sess\").setup() first")
        return false
    end

    return spec.handler(context(args)) ~= false
end

function M.setup()
    vim.api.nvim_create_user_command("Sess", function(args)
        M.execute(args)
    end, {
        nargs = "*",
        complete = complete,
    })
end

return M
