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

    local current = state.get_current_session()
    if current and current.id == session_id then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local ok, bufnr = pcall(vim.api.nvim_win_get_buf, win)
            if ok then add(bufnr) end
        end
    end
    local view = state.get_view(session_id)
    for bufnr in pairs(view and view.buffers or {}) do add(bufnr) end
    table.sort(result)
    return result
end

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

    return {
        identify = process.identify,
        list = function(_, session_id)
            local result = {}
            for _, bufnr in ipairs(session_buffers(session_id)) do
                if valid_terminal(bufnr) then
                    local agent = process.job_agent(terminal.job_id(bufnr))
                    if not agent then agent = process.command_agent(terminal.name(bufnr)) end
                    if agent then
                        result[#result + 1] = {
                            id = "terminal:" .. bufnr,
                            name = agent,
                            status = status.classify(terminal.lines(bufnr), agent),
                            target = { bufnr = bufnr },
                        }
                    end
                end
            end
            return result
        end,
        status = function(_, bufnr, name)
            if not valid_terminal(bufnr) then return nil end
            return status.classify(terminal.lines(bufnr), name)
        end,
    }
end

local default = M.new()
M.identify = default.identify
M.list = function(session_id) return default:list(session_id) end
M.status = function(bufnr, name) return default:status(bufnr, name) end

return M
