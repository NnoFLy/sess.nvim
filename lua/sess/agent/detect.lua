local state = require("sess.state")

local M = {}

local agents = {
    amp = "amp",
    agy = "agy",
    antigravity = "agy",
    claude = "claude",
    ["claude-code"] = "claude",
    cline = "cline",
    codex = "codex",
    copilot = "copilot",
    cursor = "cursor",
    ["cursor-agent"] = "cursor",
    devin = "devin",
    droid = "droid",
    gemini = "gemini",
    grok = "grok",
    hermes = "hermes",
    kilo = "kilo",
    kimi = "kimi",
    kiro = "kiro",
    letta = "letta",
    maki = "maki",
    muse = "muse",
    omp = "omp",
    opencode = "opencode",
    pi = "pi",
    qoder = "qodercli",
    qodercli = "qodercli",
    qwen = "qwen",
}

local function basename(value)
    value = value:gsub("\\", "/")
    return value:match("([^/]+)$") or value
end

local function identify(value)
    if type(value) ~= "string" then
        return nil
    end

    value = value:gsub("^%s+", "")
    local command = value:match("^([^%s%z]+)")
    if not command then
        return nil
    end

    command = basename(command):lower():gsub("%.cmd$", ""):gsub("%.exe$", "")
    return agents[command]
end

local function read_file(path)
    local ok, lines = pcall(vim.fn.readfile, path, "b")
    if not ok or type(lines) ~= "table" then
        return nil
    end
    return table.concat(lines, "\n")
end

local shells = {
    bash = true,
    cmd = true,
    fish = true,
    nu = true,
    powershell = true,
    pwsh = true,
    sh = true,
    zsh = true,
}

local function command_agent(command)
    if type(command) ~= "string" then
        return nil
    end

    local values = {}
    for value in command:gmatch("[^%z%s]+") do
        values[#values + 1] = value
    end
    if #values == 0 then
        return nil
    end

    local agent = identify(values[1])
    if agent then
        return agent
    end

    if not shells[basename(values[1]):lower()] then
        return nil
    end

    for index = 2, #values do
        agent = identify(values[index])
        if agent then
            return agent
        end
    end

    return nil
end

local function process_command(pid)
    return command_agent(read_file("/proc/" .. pid .. "/cmdline"))
end

local function child_pids(pid)
    local children = read_file("/proc/" .. pid .. "/task/" .. pid .. "/children")
    local result = {}
    for child in (children or ""):gmatch("%d+") do
        result[#result + 1] = tonumber(child)
    end
    return result
end

local function process_tree_agent(pid)
    local seen = {}
    local function visit(current, depth)
        if not current or seen[current] or depth > 8 then
            return nil
        end
        seen[current] = true

        local agent = process_command(current)
        if agent then
            return agent
        end

        for _, child in ipairs(child_pids(current)) do
            agent = visit(child, depth + 1)
            if agent then
                return agent
            end
        end

        return nil
    end

    return visit(pid, 0)
end

local function job_agent(job_id)
    if type(job_id) ~= "number" then
        return nil
    end

    local called, info = pcall(vim.fn.job_info, job_id)
    if called and type(info) == "table" then
        if info.status and info.status ~= "run" and info.status ~= "running" then
            return nil
        end

        local command = info.cmd
        local agent = type(command) == "table"
                and command_agent(table.concat(command, "\0"))
            or command_agent(command)
        if agent then
            return agent
        end
    end

    local got_pid, pid = pcall(vim.fn.jobpid, job_id)
    if got_pid and type(pid) == "number" and pid > 0 then
        return process_tree_agent(pid)
    end

    return nil
end

local function terminal_agent(bufnr)
    local called, job_id = pcall(function()
        return vim.b[bufnr].terminal_job_id
    end)
    if called then
        local agent = job_agent(job_id)
        if agent then
            return agent
        end
    end

    -- Terminal names retain the command for terminals opened with :terminal
    -- even on systems without a /proc process tree.
    local got_name, name = pcall(vim.api.nvim_buf_get_name, bufnr)
    if got_name then
        return identify(name:match("([^:]+)$"))
    end

    return nil
end

local function session_buffers(session_id)
    local current = state.get_current_session()
    if current and current.id == session_id then
        local result, seen = {}, {}
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local ok, bufnr = pcall(vim.api.nvim_win_get_buf, win)
            if ok and not seen[bufnr] then
                seen[bufnr] = true
                result[#result + 1] = bufnr
            end
        end
        return result
    end

    local view = state.get_view(session_id)
    local result = {}
    for bufnr in pairs(view and view.buffers or {}) do
        result[#result + 1] = bufnr
    end
    table.sort(result)
    return result
end

function M.list(session_id)
    local result = {}
    for _, bufnr in ipairs(session_buffers(session_id)) do
        local valid, is_valid = pcall(vim.api.nvim_buf_is_valid, bufnr)
        if valid and is_valid then
            local type_ok, buftype = pcall(function()
                return vim.bo[bufnr].buftype
            end)
            if type_ok and buftype == "terminal" then
                local agent = terminal_agent(bufnr)
                if agent then
                    result[#result + 1] = {
                        id = "terminal:" .. bufnr,
                        name = agent,
                        status = "running",
                        target = { bufnr = bufnr },
                    }
                end
            end
        end
    end
    return result
end

function M.identify(value)
    return identify(value)
end

return M
