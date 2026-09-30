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
    ["codex-cli"] = "codex",
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
    ["opencode-cli"] = "opencode",
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

    command = basename(command):lower()
    for _, extension in ipairs({ "%.cmd$", "%.exe$", "%.bat$", "%.js$", "%.mjs$", "%.cjs$" }) do
        command = command:gsub(extension, "")
    end
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

-- Terminal integrations commonly put an agent behind one of these launchers.
-- Do not scan arbitrary command arguments: a project path or prompt can contain
-- an agent name without actually starting that agent.
local command_wrappers = {
    env = true,
    exec = true,
    nohup = true,
    npm = true,
    npx = true,
    pnpm = true,
    ruby = true,
    setsid = true,
    sudo = true,
    timeout = true,
    bun = true,
    deno = true,
    node = true,
    python = true,
    python3 = true,
}

local function command_values(command)
    if type(command) == "table" then
        local values = {}
        for _, value in ipairs(command) do
            if type(value) == "string" then
                values[#values + 1] = value
            end
        end
        return values
    end

    if type(command) ~= "string" then
        return {}
    end

    local values = {}
    for value in command:gmatch("[^%z%s]+") do
        values[#values + 1] = value
    end
    return values
end

local function command_agent(command)
    local values = command_values(command)
    if #values == 0 then
        return nil
    end

    local executable = basename(values[1]):lower()
    local agent = identify(values[1])
    if agent then
        return agent
    end

    if not shells[executable] and not command_wrappers[executable] then
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
    -- Neovim exposes the process command line on supported platforms. It is
    -- preferable to parsing /proc and also lets this work on non-Linux hosts.
    local got_process, process = pcall(vim.api.nvim_get_proc, pid)
    if got_process and type(process) == "table" then
        local agent = command_agent(process.cmdline) or command_agent(process.name)
        if agent then
            return agent
        end
    end

    return command_agent(read_file("/proc/" .. pid .. "/cmdline"))
end

local function child_pids(pid)
    local got_children, children = pcall(vim.api.nvim_get_proc_children, pid)
    if got_children and type(children) == "table" and #children > 0 then
        return children
    end

    children = read_file("/proc/" .. pid .. "/task/" .. pid .. "/children")
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

    -- job_info is available in Vim but not in Neovim. Calling it through pcall
    -- keeps this compatible with both hosts; process inspection is the primary
    -- Neovim path.
    local called, info = pcall(vim.fn.job_info, job_id)
    if called and type(info) == "table" then
        if info.status and info.status ~= "run" and info.status ~= "running" then
            return nil
        end

        local agent = command_agent(info.cmd)
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
        local command = name:match("([^:]+)$")
        return command_agent(command)
    end

    return nil
end

local function terminal_lines(bufnr)
    -- Bound reads and trim screen padding before selecting recent output.
    -- A terminal can have hundreds of blank rows below its live status line.
    local line_count_ok, count = pcall(vim.api.nvim_buf_line_count, bufnr)
    if not line_count_ok then
        return nil
    end
    local lines_ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, math.max(0, count - 200), count, false)
    if not lines_ok then
        return nil
    end

    local last = #lines
    while last > 0 and vim.trim(lines[last]) == "" do
        last = last - 1
    end
    local start = math.max(1, last - 24)
    local recent = {}
    for index = start, last do
        local line = lines[index]:gsub("\r", "")
        -- Terminal buffers normally contain rendered text, but strip control
        -- sequences as well for terminals that keep them in the buffer.
        line = line:gsub("\27%][^\7]*\7", "")
        line = line:gsub("\27%[[0-?]*[ -/]*[@-~]", "")
        recent[#recent + 1] = line
    end
    return recent
end

local function contains_any(text, values)
    for _, value in ipairs(values) do
        if text:find(value, 1, true) then
            return true
        end
    end
    return false
end

local function has_input_prompt(lines)
    local line = vim.trim(lines[#lines] or "")
    -- Lua character classes are byte-based, not Unicode character sets.
    return line:sub(1, #"❯") == "❯" or line:sub(1, #"›") == "›"
end

local function terminal_status(bufnr, name)
    local lines = terminal_lines(bufnr)
    if not lines then
        return nil
    end

    local text = table.concat(lines, "\n"):lower()

    -- Blocked takes precedence over prompts: approval UIs commonly retain
    -- the agent's input marker while waiting for a decision.
    if contains_any(text, {
        "action required",
        "allow command?",
        "do you want to proceed",
        "do you want to allow",
        "would you like to",
        "esc to cancel",
        "enter to confirm",
        "enter to select",
        "[y/n]",
        "waiting for permission",
    }) then
        return "blocked"
    end

    if contains_any(text, {
        "working...",
        " to interrupt",
        "── working ──",
        "⠋ working",
        "⠙ working",
        "⠹ working",
        "⠸ working",
        "⠼ working",
        "⠴ working",
        "⠦ working",
        "⠧ working",
        "⠇ working",
        "⠏ working",
    }) then
        return "working"
    end

    if has_input_prompt(lines) then
        return "idle"
    end

    -- Pi's normal input field has no distinctive prompt marker. Other agents
    -- need positive evidence rather than silently claiming they are idle.
    return (name == "pi" or name == "omp") and "idle" or "unknown"
end

local function session_buffers(session_id)
    local result, seen = {}, {}
    local function add(bufnr)
        if not seen[bufnr] then
            seen[bufnr] = true
            result[#result + 1] = bufnr
        end
    end

    local current = state.get_current_session()
    if current and current.id == session_id then
        -- A terminal can remain live but hidden after the user changes windows.
        -- Include the current view as well as visible windows so discovery does
        -- not depend on which agent happened to be on screen when the picker
        -- opened.
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local ok, bufnr = pcall(vim.api.nvim_win_get_buf, win)
            if ok then
                add(bufnr)
            end
        end
    end

    local view = state.get_view(session_id)
    for bufnr in pairs(view and view.buffers or {}) do
        add(bufnr)
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
                        status = terminal_status(bufnr, agent) or "unknown",
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

-- Return a best-effort status for a registered terminal agent. Integrations
-- that provide an explicit status remain authoritative in the API layer.
function M.status(bufnr, name)
    local valid, is_valid = pcall(vim.api.nvim_buf_is_valid, bufnr)
    if not valid or not is_valid then
        return nil
    end

    local type_ok, buftype = pcall(function()
        return vim.bo[bufnr].buftype
    end)
    if not type_ok or buftype ~= "terminal" then
        return nil
    end

    return terminal_status(bufnr, name)
end

return M
