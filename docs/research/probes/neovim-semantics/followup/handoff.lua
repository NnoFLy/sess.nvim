-- Disposable native editor -> C broker -> independent tmux C launcher seam.
-- Bytes below are a fixture protocol, not a proposed Sess API/wire format.
local uv = vim.uv
local root = assert(vim.env.PROBE_ROOT)
local fixture = assert(vim.env.PROBE_SOCKET_FIXTURE)
local tmux_socket = assert(vim.env.PROBE_TMUX_SOCKET)
local flags = assert(tonumber(vim.env.PROBE_OPEN_FLAGS))
local function u32(n)
    return string.char(
        math.floor(n / 16777216),
        math.floor(n / 65536) % 256,
        math.floor(n / 256) % 256,
        n % 256
    )
end
local function field(s)
    return u32(#s) .. s
end
local output = {}
local function check(id, got, expected)
    table.insert(
        output,
        { id = id, got = got, expected = expected, status = got == expected and "pass" or "fail" }
    )
end
vim.cmd.lcd(root .. "/invoke")
local requested = vim.fn.getcwd()
local selected = vim.fn.exepath("true")
local fd = assert(uv.fs_open(requested, flags, 0))
local endpoint = root .. "/native.sock"
local body = field(requested) .. field(selected)
local packet = "SF01" .. u32(28 + #body) .. u32(1) .. u32(0) .. u32(2) .. u32(741) .. u32(1) .. body
local input = uv.new_pipe(false)
local out = uv.new_pipe(false)
local text, code, child_code, started = "", nil, nil, false
local broker, broker_pid
local tmux
local safe_env =
    { "PATH=/usr/bin:/bin", "HOME=" .. root .. "/home", "LANG=C.UTF-8", "TERM=xterm-256color" }
-- Only the synthetic editor snapshot has these values. Both helper bootstrap
-- processes get an explicit safe env, before the loader runs, not clearenv().
vim.env.LD_PRELOAD = assert(vim.env.PROBE_LOADER_LIBRARY)
vim.env.PROBE_LOADER_MARK = root .. "/handoff-loader.mark"
vim.env.PROBE_SECRET = "synthetic-request-only"
broker, broker_pid = assert(uv.spawn(fixture, {
    args = { "broker", endpoint, "3" },
    stdio = { input, out, nil, fd },
    env = safe_env,
}, function(exit_code)
    code = exit_code
    broker:close()
end))
uv.fs_close(fd)
uv.write(input, packet, function(err)
    assert(not err, err)
    uv.shutdown(input, function(shutdown_err)
        assert(not shutdown_err, shutdown_err)
        input:close()
    end)
end)
uv.read_start(out, function(err, data)
    assert(not err, err)
    if not data then
        out:close()
        return
    end
    text = text .. data
    if not started and text:find("BOUND\n", 1, true) then
        started = true
        vim.schedule(function()
            -- Broker holds the original live object after the editor closes fd.
            vim.cmd.tabnew()
            vim.cmd.lcd(root .. "/placed")
            check("NATIVE-HANDOFF-placement-changed-after-pin", vim.fn.getcwd() ~= requested, true)
            tmux = assert(uv.spawn("/usr/bin/tmux", {
                args = {
                    "-N",
                    "-S",
                    tmux_socket,
                    "new-window",
                    "-d",
                    "-t",
                    "probe:",
                    "--",
                    fixture,
                    "launcher",
                    endpoint,
                    tostring(broker_pid),
                    "741",
                },
                stdio = { nil, nil, nil },
                env = safe_env,
            }, function(exit_code)
                child_code = exit_code
                tmux:close()
            end))
        end)
    end
end)
assert(vim.wait(7000, function()
    return code ~= nil and child_code ~= nil and out:is_closing()
end))
check(
    "NATIVE-HANDOFF-C-broker-SCM_RIGHTS-final-cwd-exchange",
    code == 0 and text == "BOUND\nACCEPTED_EXEC_UNVERIFIED\n",
    true
)
check("NATIVE-HANDOFF-tmux-zero-not-exec-proof", child_code, 0)
check(
    "NATIVE-HANDOFF-before-loader-clean-positive-exchange",
    code == 0
        and text == "BOUND\nACCEPTED_EXEC_UNVERIFIED\n"
        and uv.fs_stat(root .. "/handoff-loader.mark") == nil,
    true
)
vim.fn.writefile({ vim.json.encode(output) }, root .. "/handoff.json")
vim.cmd("qa!")
