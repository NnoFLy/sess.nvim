-- Disposable native luv FD seam; constants come from the compiled system headers.
local uv = vim.uv
local root = assert(vim.env.PROBE_ROOT)
local fixture = assert(vim.env.PROBE_FIXTURE)
local flags = assert(tonumber(vim.env.PROBE_OPEN_FLAGS))
local output = {}
local function check(id, got, expected)
    table.insert(
        output,
        { id = id, got = got, expected = expected, status = got == expected and "pass" or "fail" }
    )
end
vim.cmd.lcd(root .. "/invoke")
local requested = vim.fn.getcwd()
-- Captured workload inputs must not influence the broker's loader/startup.
vim.env.LD_PRELOAD = assert(vim.env.PROBE_LOADER_LIBRARY)
vim.env.PROBE_LOADER_MARK = root .. "/native-loader.mark"
vim.env.PROBE_SECRET = "synthetic-request-only"
local fd, err = uv.fs_open(requested, flags, 0)
check("FD-O_PATH-open", fd ~= nil, true)
local child_ok = false
if fd then
    local pipe = uv.new_pipe(false)
    local text = ""
    local code
    local handle
    handle = assert(uv.spawn(fixture, {
        args = { "inherited", requested },
        stdio = { nil, pipe, nil, fd },
        env = { "PATH=/usr/bin:/bin" },
    }, function(exit_code)
        code = exit_code
        handle:close()
    end))
    uv.read_start(pipe, function(read_err, data)
        assert(not read_err, read_err)
        if data then
            text = text .. data
        else
            pipe:close()
        end
    end)
    uv.fs_close(fd)
    vim.cmd.tabnew()
    vim.cmd.lcd(root .. "/placed")
    check("FD-invoking-cwd-captured-before-placement", vim.fn.getcwd() ~= requested, true)
    assert(vim.wait(5000, function()
        return code ~= nil and pipe:is_closing()
    end))
    check("FD-luv-numeric-stdio-3-reference-survives-parent-close", text, "PINNED\n")
    check("FD-inherited-child-exit", code, 0)
    child_ok = code == 0 and text == "PINNED\n"
else
    -- Error names are safe; no environment or payload is emitted.
    check("FD-open-error", err and err:match("^[A-Z]+") or "unknown", "none")
end
check(
    "BOOTSTRAP-native-clean-env-positive-child-no-loader",
    child_ok and uv.fs_stat(root .. "/native-loader.mark") == nil,
    true
)
vim.env.LD_PRELOAD = nil
vim.env.PROBE_LOADER_MARK = nil
vim.env.PROBE_SECRET = nil
-- Native direct argv must choose the invoking PATH/cwd before child overrides.
vim.cmd.lcd(root .. "/invoke")
vim.env.PATH = root .. "/invoke/bin:/usr/bin:/bin"
local selected = vim.fn.exepath("pick")
check("LOOKUP-native-exepath-before-placement", selected == root .. "/invoke/bin/pick", true)
vim.cmd.tabnew()
vim.cmd.lcd(root .. "/placed")
check("LOOKUP-selection-carried-after-placement", selected == root .. "/invoke/bin/pick", true)
vim.cmd.lcd(root .. "/invoke")
for _, term in ipairs({ false, true }) do
    local text = ""
    local code
    local job = vim.fn.jobstart({ "pick", "literal;#{pane_id}" }, {
        term = term,
        cwd = root .. "/placed",
        env = { PATH = root .. "/placed/bin" },
        on_stdout = function(_, data)
            text = text .. table.concat(data, "\n")
        end,
        on_exit = function(_, exit_code)
            code = exit_code
        end,
    })
    check("LOOKUP-native-jobstart-created-" .. tostring(term), job > 0, true)
    assert(vim.wait(5000, function()
        return code ~= nil
    end))
    check(
        "LOOKUP-native-ENOEXEC-invoking-selection-" .. tostring(term),
        text:find("INVOKING:literal;#{pane_id}", 1, true) ~= nil,
        true
    )
    check("LOOKUP-native-ENOEXEC-exit-" .. tostring(term), code, 0)
    if term then
        vim.cmd.enew()
    end
end
check("FD-luv-O_PATH-constant-unavailable", uv.constants.O_PATH == nil, true)
vim.fn.writefile({ vim.json.encode(output) }, root .. "/capture.json")
vim.cmd("qa!")
