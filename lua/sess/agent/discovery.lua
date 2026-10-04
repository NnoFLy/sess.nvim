local state = require("sess.state")
local default_process = require("sess.agent.process_probe")
local default_terminal = require("sess.agent.terminal_probe")
local default_status = require("sess.agent.status")

local M = {}

local function session_buffers(session_id)
    local result, seen = {}, {}
    local function add(bufnr)
        if not seen[bufnr] then seen[bufnr] = true; result[#result + 1] = bufnr end
    end

    if state.is_current_session(session_id) then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local ok, bufnr = pcall(vim.api.nvim_win_get_buf, win)
            if ok then add(bufnr) end
        end
    end
    for _, bufnr in ipairs(state.get_view_buffers(session_id)) do add(bufnr) end
    table.sort(result)
    return result
end

local function now_ms()
    local uv = vim.uv or vim.loop
    if uv and uv.hrtime then
        return uv.hrtime() / 1000000
    end
    return os.clock() * 1000
end

local IDENTITY_CACHE_TTL = 5000

local function valid_terminal(bufnr)
    local ok, valid = pcall(vim.api.nvim_buf_is_valid, bufnr)
    if not ok or not valid then return false end
    local type_ok, buftype = pcall(function() return vim.bo[bufnr].buftype end)
    return type_ok and buftype == "terminal"
end

function M.new(probes)
    probes = probes or {}
    local process = probes.process or default_process
    local terminal = probes.terminal or default_terminal
    local status = probes.status or default_status
    local identity_cache = {}
    local status_cache = {}

    local function discover(bufnr, use_cache)
        local job_id = terminal.job_id(bufnr)
        local terminal_name = terminal.name(bufnr)
        local cached = identity_cache[bufnr]
        local now = now_ms()
        if use_cache
            and cached
            and cached.job_id == job_id
            and cached.terminal_name == terminal_name
            and cached.expires_at > now
        then
            return cached.agent
        end

        local agent = process.job_agent(job_id)
        if not agent then agent = process.command_agent(terminal_name) end
        identity_cache[bufnr] = {
            job_id = job_id,
            terminal_name = terminal_name,
            agent = agent,
            expires_at = now + IDENTITY_CACHE_TTL,
        }
        return agent
    end

    local function classify(bufnr, name, use_cache)
        local changedtick = terminal.changedtick and terminal.changedtick(bufnr)
        local cached = status_cache[bufnr]
        if use_cache
            and changedtick ~= nil
            and cached
            and cached.name == name
            and cached.changedtick == changedtick
        then
            return cached.value
        end

        local value = status.classify(terminal.lines(bufnr), name)
        if changedtick ~= nil then
            status_cache[bufnr] = { name = name, changedtick = changedtick, value = value }
        else
            status_cache[bufnr] = nil
        end
        return value
    end

    return {
        identify = process.identify,
        list = function(_, session_id, options)
            local use_cache = options and options.cache == true
            local result = {}
            for _, bufnr in ipairs(session_buffers(session_id)) do
                if valid_terminal(bufnr) then
                    local agent = discover(bufnr, use_cache)
                    if agent then
                        result[#result + 1] = {
                            id = "terminal:" .. bufnr,
                            name = agent,
                            status = classify(bufnr, agent, use_cache),
                            target = { bufnr = bufnr },
                        }
                    end
                else
                    identity_cache[bufnr] = nil
                    status_cache[bufnr] = nil
                end
            end
            return result
        end,
        status = function(_, bufnr, name, options)
            if not valid_terminal(bufnr) then return nil end
            return classify(bufnr, name, options and options.cache == true)
        end,
    }
end

local default = M.new()
M.identify = default.identify
M.list = function(session_id, options) return default:list(session_id, options) end
M.status = function(bufnr, name, options) return default:status(bufnr, name, options) end

return M
