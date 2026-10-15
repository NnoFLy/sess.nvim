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
local MAX_TREE_DEPTH = 8
local MAX_VISITED_PROCESSES = 256
local MAX_COMMAND_TOKENS = 64
local MAX_COMMAND_BYTES = 32768
local MAX_TOKEN_BYTES = 4096
local MAX_CHILDREN = 256
local MAX_DIAGNOSTIC_BYTES = 160

local function probe_diagnostic(message)
    message = tostring(message)
    if #message > MAX_DIAGNOSTIC_BYTES then message = message:sub(1, MAX_DIAGNOSTIC_BYTES) end
    return message
end

local function basename(value)
    value = value:gsub("\\", "/")
    return value:match("([^/]+)$") or value
end

function M.identify(value)
    if type(value) ~= "string" or #value > MAX_TOKEN_BYTES then return nil end
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
        local bytes = 0
        for key in pairs(command) do
            if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #command then
                return nil, probe_diagnostic("process command argv is malformed")
            end
        end
        if #command > MAX_COMMAND_TOKENS then
            return nil, probe_diagnostic("process command argv was truncated")
        end
        for index = 1, #command do
            local value = command[index]
            if type(value) ~= "string" then
                return nil, probe_diagnostic("process command argv contains a malformed token")
            end
            bytes = bytes + #value
            if #value > MAX_TOKEN_BYTES then
                return nil, probe_diagnostic("process command argv token is too long")
            end
            if bytes > MAX_COMMAND_BYTES then
                return nil, probe_diagnostic("process command argv was truncated")
            end
            result[#result + 1] = value
        end
        return result
    end
    if type(command) ~= "string" then
        return nil, probe_diagnostic("process command line is malformed")
    end
    if #command > MAX_COMMAND_BYTES then
        return nil, probe_diagnostic("process command line was truncated")
    end
    local result = {}
    local bytes = 0
    for value in command:gmatch("[^%z%s]+") do
        if #value > MAX_TOKEN_BYTES then
            return nil, probe_diagnostic("process command token is too long")
        end
        bytes = bytes + #value
        if #result >= MAX_COMMAND_TOKENS or bytes > MAX_COMMAND_BYTES then
            return nil, probe_diagnostic("process command line was truncated")
        end
        result[#result + 1] = value
    end
    return result
end

function M.command_agent(command)
    local parts, parse_diagnostic = values(command)
    if parse_diagnostic then return nil, parse_diagnostic end
    if #parts == 0 then return nil end
    local executable = basename(parts[1]):lower()
    local agent = M.identify(parts[1])
    if agent then return agent end

    -- Shell payloads are opaque text, not argv entries. Looking through them
    -- turns commands such as `sh -c 'echo codex'` into false identities.
    if shells[executable] then return nil end
    if not wrappers[executable] then return nil end

    local function next_command(first, mode)
        local index = first
        local skipped_value = false
        local wrapper_value_options = {
            ["-p"] = true,
            ["--package"] = true,
            ["--prefix"] = true,
            ["--cache"] = true,
            ["--userconfig"] = true,
            ["--registry"] = true,
            ["--node-options"] = true,
        }
        while index <= #parts do
            local value = parts[index]
            if value == "--" then return index + 1 end
            if value:match("^[A-Za-z_][A-Za-z0-9_]*=") then
                index = index + 1
            elseif value:sub(1, 1) == "-" then
                if mode == "runtime"
                    and (value == "-c" or value == "-e" or value == "--eval" or value == "--command")
                then
                    -- The following token is program text, not an executable.
                    return nil
                end
                local requires_value = (mode == "sudo"
                        and (value == "-u" or value == "--user" or value == "-g" or value == "--group"
                            or value == "-C" or value == "--chdir" or value == "-r" or value == "--role"))
                    or (mode == "env" and (value == "-u" or value == "--unset" or value == "-C" or value == "--chdir"))
                    or ((mode == "exec" or mode == "nohup") and (value == "-a" or value == "--argv0"))
                    or ((mode == "package" or mode == "exec") and wrapper_value_options[value])
                    or (mode == "runtime" and (
                        value == "-m" or value == "--module" -- python module name
                        or value == "-r" or value == "--require" -- node/ruby module
                        or value == "--import" or value == "--loader" or value == "--experimental-loader"
                        or value == "--import-map" or value == "--config" or value == "--project"
                    ))
                if mode == "runtime" and not requires_value then
                    local option, attached = value:match("^([^=]+)=(.*)$")
                    local attached_value = option and attached ~= "" and ({
                        ["-m"] = true,
                        ["--module"] = true,
                        ["-r"] = true,
                        ["--require"] = true,
                        ["--import"] = true,
                        ["--loader"] = true,
                        ["--experimental-loader"] = true,
                        ["--import-map"] = true,
                        ["--config"] = true,
                        ["--project"] = true,
                    })[option]
                    if not attached_value then
                        -- Runtime flags are not executable positions. Unknown
                        -- flags may consume a value, so stop rather than
                        -- inspecting a later token as though it were the script.
                        return nil
                    end
                    index = index + 1
                else
                    index = index + (requires_value and 2 or 1)
                end
            elseif mode == "timeout" and not skipped_value then
                -- timeout's first positional argument is a duration, not a
                -- command. Do not inspect it or later payload text as an argv
                -- command unless a structural command token follows.
                skipped_value = true
                index = index + 1
            else
                return index
            end
        end
    end

    local command_index
    if executable == "env" then
        command_index = next_command(2, "env")
    elseif executable == "exec" or executable == "nohup" or executable == "setsid" then
        command_index = next_command(2, executable)
    elseif executable == "sudo" then
        command_index = next_command(2, "sudo")
    elseif executable == "timeout" then
        command_index = next_command(2, "timeout")
    else
        -- Runtime and package-manager wrappers identify only their structural
        -- command position, never an arbitrary option value or payload.
        local runtime = executable == "node" or executable == "deno" or executable == "bun"
            or executable == "python" or executable == "python3" or executable == "ruby"
        local package_wrapper = executable == "npm" or executable == "npx" or executable == "pnpm"
        local mode = executable
        if runtime then
            mode = "runtime"
        elseif package_wrapper then
            mode = "package"
        end
        command_index = next_command(2, mode)
    end
    if not command_index then return nil end

    local candidate = M.identify(parts[command_index])
    if candidate then return candidate end
    -- A nested recognized wrapper (for example `env exec codex`) is safe to
    -- inspect because its command position is still structurally known.
    local nested = basename(parts[command_index]):lower()
    if wrappers[nested] then
        local nested_parts = {}
        for index = command_index, #parts do nested_parts[#nested_parts + 1] = parts[index] end
        return M.command_agent(nested_parts)
    end
    return nil
end

local function read_file(path)
    local ok, lines = pcall(vim.fn.readfile, path, "b")
    if not ok or type(lines) ~= "table" then return nil end
    local bytes = 0
    for _, line in ipairs(lines) do
        if type(line) ~= "string" then return nil, probe_diagnostic("process file contents are malformed") end
        bytes = bytes + #line
        if bytes > MAX_COMMAND_BYTES then return nil, probe_diagnostic("process file contents were truncated") end
    end
    return table.concat(lines, "\n")
end

local function valid_pid(pid)
    return type(pid) == "number" and pid % 1 == 0 and pid > 0
end

function M.process(pid)
    if not valid_pid(pid) then return nil, probe_diagnostic("process id is malformed") end
    local ok, process = pcall(vim.api.nvim_get_proc, pid)
    if ok and type(process) == "table" then
        -- nvim_get_proc() does not expose argv on all supported versions.
        -- Supplement the bounded process record with /proc cmdline when it is
        -- available so wrapper-launched agents can still be identified.
        if process.cmdline == nil and process.cmd == nil then
            local command, read_diagnostic = read_file("/proc/" .. pid .. "/cmdline")
            if command then process.cmdline = command end
            if read_diagnostic then process.cmdline_diagnostic = read_diagnostic end
        end
        return process
    end
    local command, read_diagnostic = read_file("/proc/" .. pid .. "/cmdline")
    if read_diagnostic then return nil, read_diagnostic end
    return command and { cmdline = command } or nil
end

function M.children(pid)
    if not valid_pid(pid) then return {}, probe_diagnostic("process id is malformed") end
    local ok, children = pcall(vim.api.nvim_get_proc_children, pid)
    if ok and type(children) == "table" and #children > 0 then
        if #children > MAX_CHILDREN then return {}, probe_diagnostic("process child list was truncated") end
        for key in pairs(children) do
            if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #children then
                return {}, probe_diagnostic("process child list is malformed")
            end
        end
        local result = {}
        for _, child in ipairs(children) do
            if not valid_pid(child) then return {}, probe_diagnostic("process child list is malformed") end
            result[#result + 1] = child
        end
        return result
    end
    local raw, read_diagnostic = read_file("/proc/" .. pid .. "/task/" .. pid .. "/children")
    if read_diagnostic then return {}, read_diagnostic end
    local result = {}
    for token in (raw or ""):gmatch("%S+") do
        if #result >= MAX_CHILDREN then return {}, probe_diagnostic("process child list was truncated") end
        if not token:match("^%d+$") then return {}, probe_diagnostic("process child list is malformed") end
        local child = tonumber(token)
        if not valid_pid(child) then return {}, probe_diagnostic("process child list is malformed") end
        result[#result + 1] = child
    end
    return result
end

function M.tree_agent(pid)
    local seen = {}
    local visited = 0
    local diagnostics = {}
    local function add_diagnostic(message)
        if message and #diagnostics == 0 then diagnostics[1] = message end
    end
    local function visit(current, depth)
        if not current or seen[current] or depth > MAX_TREE_DEPTH or visited >= MAX_VISITED_PROCESSES then return nil end
        seen[current] = true
        visited = visited + 1
        local process, process_diagnostic = M.process(current)
        add_diagnostic(process_diagnostic)
        local agent, command_diagnostic
        if process then
            agent, command_diagnostic = M.command_agent(process.cmdline or process.cmd)
            add_diagnostic(command_diagnostic or process.cmdline_diagnostic)
            if not agent then
                local name_diagnostic
                agent, name_diagnostic = M.command_agent(process.name)
                add_diagnostic(name_diagnostic)
            end
        end
        if agent then return agent end
        local children, children_diagnostic = M.children(current)
        add_diagnostic(children_diagnostic)
        table.sort(children)
        for _, child in ipairs(children) do
            agent = visit(child, depth + 1)
            if agent then return agent end
        end
    end
    local agent = visit(pid, 0)
    return agent, diagnostics[1]
end

function M.job_agent(job_id)
    if type(job_id) ~= "number" then return nil, probe_diagnostic("job id is malformed") end
    local diagnostic
    local called, info = pcall(vim.fn.job_info, job_id)
    if called and type(info) == "table" then
        if info.status and info.status ~= "run" and info.status ~= "running" then return nil end
        local agent, command_diagnostic = M.command_agent(info.cmd)
        diagnostic = command_diagnostic
        if agent then return agent, diagnostic end
    end
    local got_pid, pid = pcall(vim.fn.jobpid, job_id)
    if got_pid and valid_pid(pid) then
        local agent, tree_diagnostic = M.tree_agent(pid)
        return agent, tree_diagnostic or diagnostic
    end
    return nil, diagnostic
end

return M
