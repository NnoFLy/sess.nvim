-- Editor-adapter policy for automatic startup transitions. No persistence here.
local M = {}

local registration = 0
local attempted = false
local stdin_read = false
local interacted = false
local input_namespace = vim.api.nvim_create_namespace("sess.startup.input")

local function stop_listening(token)
    if token == registration then
        vim.on_key(nil, input_namespace)
    end
end

-- Consume option operands before interpreting file/command roles. In particular,
-- a config, shada, log, or socket path beginning with '+' is not a +command.
local function implicit_startup()
    local argv = vim.v.argv
    local operands = { ["--listen"] = true, ["--server"] = true, ["--startuptime"] = true }
    local flags =
        { ["--headless"] = true, ["--embed"] = true, ["--clean"] = true, ["--noplugin"] = true }
    local index = 2
    while index <= #argv do
        local arg = argv[index]
        if arg == "--" then
            return index == #argv
        elseif arg:sub(1, 1) == "+" or arg == "-" or arg:sub(1, 1) ~= "-" then
            return false
        elseif operands[arg] then
            index = index + 1
            if not argv[index] then
                return false
            end
        elseif not flags[arg] then
            if arg:sub(1, 2) == "--" then
                return false
            end
            local offset = 2
            while offset <= #arg do
                local option = arg:sub(offset, offset)
                if option:match("[cSsltqeE]") then
                    -- Commands, sourced input, tag/quickfix requests are explicit.
                    return false
                elseif option:match("[uiwW]") then
                    if offset == #arg then
                        index = index + 1
                        if not argv[index] then
                            return false
                        end
                    end
                    break
                elseif option == "V" then
                    -- Optional verbosity/file suffix belongs to -V itself.
                    break
                elseif option:match("[oOp]") then
                    local digits = arg:sub(offset + 1):match("^%d*")
                    offset = offset + #digits
                elseif not option:match("[nRbmMAHd]") then
                    return false
                end
                offset = offset + 1
            end
        end
        index = index + 1
    end
    return true
end

local function eligible()
    local state = require("sess.state")
    if
        vim.v.this_session ~= ""
        or state.get_current_session()
        or #state.get_active_sessions() > 0
        or state.has_managed_sessions()
    then
        return nil
    end
    return true
end

---@param group integer Managed augroup, cleared by the event adapter on setup.
---@param mode "none"|"current"|"all"
---@param callback fun(mode: string)
function M.setup(group, mode, callback)
    vim.on_key(nil, input_namespace)
    registration = registration + 1
    local token = registration
    if mode == "none" or attempted or vim.v.vim_did_enter ~= 0 then
        return
    end
    -- Only typed input carries user provenance. Buffer/window changes and
    -- non-typed feedkeys from plugins must not cancel startup restoration.
    vim.on_key(function(_, typed)
        if typed and typed ~= "" then
            interacted = true
            stop_listening(token)
        end
    end, input_namespace)
    vim.api.nvim_create_autocmd("StdinReadPre", {
        group = group,
        callback = function()
            stdin_read = true
        end,
    })
    vim.api.nvim_create_autocmd("VimEnter", {
        group = group,
        once = true,
        callback = function()
            if interacted or stdin_read or not implicit_startup() or not eligible() then
                stop_listening(token)
                return
            end
            vim.schedule(function()
                if
                    token ~= registration
                    or attempted
                    or interacted
                    or stdin_read
                    or not implicit_startup()
                    or not eligible()
                then
                    stop_listening(token)
                    return
                end
                stop_listening(token)
                attempted = true
                callback(mode)
            end)
        end,
    })
end

return M
