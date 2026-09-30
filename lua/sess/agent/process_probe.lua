local M = {}

local agents = {
    amp = "amp", agy = "agy", antigravity = "agy", claude = "claude",
    ["claude-code"] = "claude", cline = "cline", codex = "codex",
    ["codex-cli"] = "codex", copilot = "copilot", cursor = "cursor",
    ["cursor-agent"] = "cursor", devin = "devin", droid = "droid",
    gemini = "gemini", grok = "grok", hermes = "hermes", kilo = "kilo",
    kimi = "kimi", kiro = "kiro", letta = "letta", maki = "maki",
    muse = "muse", omp = "omp", opencode = "opencode",
    ["opencode-cli"] = "opencode", pi = "pi", qoder = "qodercli",
    qodercli = "qodercli", qwen = "qwen",
}

local shells = { bash = true, cmd = true, fish = true, nu = true, powershell = true, pwsh = true, sh = true, zsh = true }
local wrappers = {
    env = true, exec = true, nohup = true, npm = true, npx = true, pnpm = true,
    ruby = true, setsid = true, sudo = true, timeout = true, bun = true,
    deno = true, node = true, python = true, python3 = true,
}

local function basename(value)
    value = value:gsub("\\", "/")
    return value:match("([^/]+)$") or value
end

function M.identify(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", "")
    local command = value:match("^([^%s%z]+)")
    if not command then return nil end
    command = basename(command):lower()
    for _, extension in ipairs({ "%.cmd$", "%.exe$", "%.bat$", "%.js$", "%.mjs$", "%.cjs$" }) do
        command = command:gsub(extension, "")
    end
    return agents[command]
end

local function values(command)
    if type(command) == "table" then
        local result = {}
        for _, value in ipairs(command) do
            if type(value) == "string" then result[#result + 1] = value end
        end
        return result
    end
    if type(command) ~= "string" then return {} end
    local result = {}
    for value in command:gmatch("[^%z%s]+") do result[#result + 1] = value end
    return result
end

function M.command_agent(command)
    local parts = values(command)
    if #parts == 0 then return nil end
    local executable = basename(parts[1]):lower()
    local agent = M.identify(parts[1])
    if agent then return agent end
    if not shells[executable] and not wrappers[executable] then return nil end
    for index = 2, #parts do
        agent = M.identify(parts[index])
        if agent then return agent end
    end
    return nil
end

local function read_file(path)
    local ok, lines = pcall(vim.fn.readfile, path, "b")
    return ok and type(lines) == "table" and table.concat(lines, "\n") or nil
end

function M.process(pid)
    local ok, process = pcall(vim.api.nvim_get_proc, pid)
    if ok and type(process) == "table" then return process end
    local command = read_file("/proc/" .. pid .. "/cmdline")
    return command and { cmdline = command } or nil
end

function M.children(pid)
    local ok, children = pcall(vim.api.nvim_get_proc_children, pid)
    if ok and type(children) == "table" and #children > 0 then return children end
    local raw = read_file("/proc/" .. pid .. "/task/" .. pid .. "/children")
    local result = {}
    for child in (raw or ""):gmatch("%d+") do result[#result + 1] = tonumber(child) end
    return result
end

function M.tree_agent(pid)
    local seen = {}
    local function visit(current, depth)
        if not current or seen[current] or depth > 8 then return nil end
        seen[current] = true
        local process = M.process(current)
        local agent = process and (M.command_agent(process.cmdline) or M.command_agent(process.name))
        if agent then return agent end
        for _, child in ipairs(M.children(current)) do
            agent = visit(child, depth + 1)
            if agent then return agent end
        end
    end
    return visit(pid, 0)
end

function M.job_agent(job_id)
    if type(job_id) ~= "number" then return nil end
    local called, info = pcall(vim.fn.job_info, job_id)
    if called and type(info) == "table" then
        if info.status and info.status ~= "run" and info.status ~= "running" then return nil end
        local agent = M.command_agent(info.cmd)
        if agent then return agent end
    end
    local got_pid, pid = pcall(vim.fn.jobpid, job_id)
    if got_pid and type(pid) == "number" and pid > 0 then return M.tree_agent(pid) end
end

return M
