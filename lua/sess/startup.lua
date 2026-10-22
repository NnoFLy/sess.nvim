-- Editor-adapter policy for automatic startup transitions. No persistence here.
local M = {}

local registration = 0
local attempted = false
local stdin_read = false

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

local function capture()
    local state = require("sess.state")
    if
        vim.v.this_session ~= ""
        or state.get_current_session()
        or #state.get_active_sessions() > 0
    then
        return nil
    end
    if #vim.api.nvim_list_tabpages() ~= 1 or #vim.api.nvim_list_wins() ~= 1 then
        return nil
    end
    local win = vim.api.nvim_get_current_win()
    local config = vim.api.nvim_win_get_config(win)
    if
        config.relative ~= ""
        or config.external
        or vim.fn.haslocaldir() ~= 0
        or vim.fn.haslocaldir(-1, 0) ~= 0
    then
        return nil
    end
    local buf = vim.api.nvim_get_current_buf()
    if
        vim.bo[buf].buftype ~= ""
        or vim.bo[buf].modified
        or vim.api.nvim_buf_get_name(buf) ~= ""
        or vim.api.nvim_buf_line_count(buf) ~= 1
        or vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] ~= ""
    then
        return nil
    end
    local buffers = {}
    for _, candidate in ipairs(vim.api.nvim_list_bufs()) do
        local loaded = vim.api.nvim_buf_is_loaded(candidate)
        local entry = {
            name = vim.api.nvim_buf_get_name(candidate),
            kind = vim.bo[candidate].buftype,
            modified = vim.bo[candidate].modified,
            listed = vim.bo[candidate].buflisted,
            loaded = loaded,
            tick = vim.api.nvim_buf_get_changedtick(candidate),
            line_count = loaded and vim.api.nvim_buf_line_count(candidate) or nil,
            first_line = loaded and vim.api.nvim_buf_get_lines(candidate, 0, 1, false)[1] or nil,
        }
        if
            candidate ~= buf
            and (
                entry.name ~= ""
                or entry.kind ~= ""
                or entry.modified
                or entry.listed
                or (loaded and (entry.line_count ~= 1 or entry.first_line ~= ""))
            )
        then
            return nil
        end
        buffers[candidate] = entry
    end
    return {
        buf = buf,
        buffers = buffers,
        win = win,
        tab = vim.api.nvim_get_current_tabpage(),
        config = config,
        width = vim.api.nvim_win_get_width(win),
        height = vim.api.nvim_win_get_height(win),
        view = vim.fn.winsaveview(),
        cwd = vim.fn.getcwd(),
        global_cwd = vim.fn.getcwd(-1, -1),
        generation = state.get_active_generation(),
    }
end

---@param group integer Managed augroup, cleared by the event adapter on setup.
---@param mode "none"|"current"|"all"
---@param callback fun(mode: string)
function M.setup(group, mode, callback)
    registration = registration + 1
    local token = registration
    if mode == "none" or attempted or vim.v.vim_did_enter ~= 0 then
        return
    end
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
            if stdin_read or not implicit_startup() then
                return
            end
            local stamp = capture()
            if not stamp then
                return
            end
            vim.schedule(function()
                if
                    token ~= registration
                    or attempted
                    or stdin_read
                    or not implicit_startup()
                    or not vim.deep_equal(stamp, capture())
                then
                    return
                end
                attempted = true
                callback(mode)
            end)
        end,
    })
end

return M
