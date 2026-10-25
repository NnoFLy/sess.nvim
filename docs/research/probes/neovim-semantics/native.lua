-- Disposable native semantics, not a Sess adapter. Run only through run.py.
local root = assert(vim.env.PROBE_ROOT)
local fixture = root .. "/shell recorder"
local results = {}
local serial = 0
local function check(id, got, expected)
    results[#results + 1] = {
        id = id,
        status = vim.deep_equal(got, expected) and "pass" or "fail",
        got = got,
        expected = expected,
    }
end
local function fresh()
    vim.cmd("silent! tabonly!")
    vim.cmd("silent! only!")
    vim.cmd("enew!")
    vim.bo.bufhidden = "hide"
end
local function outpath()
    serial = serial + 1
    local out = root .. "/native-" .. serial .. ".json"
    vim.env.PROBE_OUT = out
    return out
end
local function collect(out, job)
    assert(
        vim.wait(3000, function()
            return vim.fn.filereadable(out) == 1
        end, 5),
        "child output timed out"
    )
    if job then
        vim.fn.jobwait({ job }, 3000)
    end
    return vim.json.decode(table.concat(vim.fn.readfile(out), "\n"))
end
local function job(command, opts)
    fresh()
    local out = outpath()
    local id = vim.fn.jobstart(command, vim.tbl_extend("force", { term = true }, opts or {}))
    assert(id > 0, "job failed")
    return collect(out, id)
end
local function context()
    fresh()
    vim.cmd("edit " .. vim.fn.fnameescape(root .. "/alternate.txt"))
    vim.cmd("edit " .. vim.fn.fnameescape(root .. "/current file.txt"))
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "word path/to/file.lua" })
    vim.bo.modified = false
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
end
local function ex(tail)
    context()
    local out = outpath()
    vim.cmd("terminal " .. tail)
    return collect(out, vim.b.terminal_job_id)
end
local ok, err = pcall(function()
    vim.o.hidden = true
    vim.o.shell = '"' .. fixture .. '"'
    vim.o.shellcmdflag = "-c"
    vim.o.shellxquote = ""
    vim.o.shellquote = ""
    vim.o.shellxescape = ""
    local function exargs(id, text, expected)
        check(id, ex(text).argv, { "-c", expected })
    end
    exargs(
        "EX-percent-quotes",
        [['%' "%"]],
        "'" .. root .. "/current file.txt' \"" .. root .. '/current file.txt"'
    )
    exargs("EX-alternate", "#", root .. "/alternate.txt")
    exargs("EX-cword-cfile", "<cword> <cfile>", "path path/to/file.lua")
    exargs("EX-modifiers", "%:t:r %:e %:p:h <cfile>:t", "current file txt " .. root .. " file.lua")
    exargs("EX-substitution-modifier", "%:t:s/current/other/", "other file.txt")
    exargs("EX-shell-escape", "%:S", "'" .. root .. "/current file.txt'")
    exargs("EX-backslash", [[\% \# \<cword> \\%]], [[% # <cword> \%]])
    exargs(
        "EX-pipe-quote-backslash",
        [[echo 'x y' "z" \\foo | cat]],
        [[echo 'x y' "z" \\foo | cat]]
    )
    exargs("EX-env-tilde-left-to-shell", [[$PROBE_VALUE ~ *.txt]], [[$PROBE_VALUE ~ *.txt]])
    -- Expansion failures must happen before view creation/TermOpen, not only fail the child.
    local opened = 0
    vim.api.nvim_create_autocmd("TermOpen", {
        callback = function()
            opened = opened + 1
        end,
    })
    fresh()
    local before = vim.api.nvim_get_current_buf()
    local count = opened
    local success, message = pcall(vim.cmd, "terminal %")
    check("EX-missing-percent-no-view", {
        success,
        vim.api.nvim_get_current_buf() == before,
        opened == count,
        tostring(message):match("E499") ~= nil,
    }, { false, true, true, true })
    context()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
    vim.bo.modified = false
    before = vim.api.nvim_get_current_buf()
    count = opened
    success, message = pcall(vim.cmd, "terminal <cword>")
    check("EX-missing-cword-no-view", {
        success,
        vim.api.nvim_get_current_buf() == before,
        opened == count,
        tostring(message):match("E348") ~= nil,
    }, { false, true, true, true })
    for _, special in ipairs({ "#999999", "<cfile>" }) do
        context()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
        vim.bo.modified = false
        before = vim.api.nvim_get_current_buf()
        count = opened
        success = pcall(vim.cmd, "terminal " .. special)
        check(
            "EX-invalid-expansion-" .. special,
            { success, vim.api.nvim_get_current_buf() == before, opened == count },
            { false, true, true }
        )
    end
    -- String jobstart deliberately does no Ex expansion.
    check("JOB-string-no-Ex", job("% # <cword>").argv, { "-c", "% # <cword>" })
    check("JOB-empty-string", job("").argv, { "-c", "" })
    check("EX-omitted-shell", ex("").argv, {})
    check("EX-whitespace-shell", ex("   ").argv, {})
    vim.o.shell = '"' .. fixture .. '" "shell arg"'
    vim.o.shellcmdflag = '-c "flag arg"'
    vim.o.shellquote = "IGNORED"
    check(
        "SHELL-double-quote-tokenization-shellquote-ignored",
        job("text").argv,
        { "shell arg", "-c", "flag arg", "text" }
    )
    check("SHELL-omitted-no-command-flags", ex("").argv, { "shell arg" })
    vim.o.shell = '"' .. fixture .. '"'
    vim.o.shellcmdflag = "-c 'two words'"
    check("SHELL-single-quotes-not-grouping", job("text").argv, { "-c", "'two", "words'", "text" })
    vim.o.shellcmdflag = "-c"
    vim.o.shellxquote = '"'
    check("SHELL-xquote", job("a & b").argv, { "-c", '"a & b"' })
    vim.o.shellxquote = "("
    vim.o.shellxescape = "&"
    check("SHELL-xescape-parentheses", job("a & b").argv, { "-c", "(a ^& b)" })
    vim.o.shellxquote = ""
    check("SHELL-xescape-inactive", job("a & b").argv, { "-c", "a & b" })
    vim.o.shellxescape = ""
    vim.o.shell = root .. "/missing-shell"
    local before_files = #vim.fn.glob(root .. "/native-*.json", false, true)
    success = pcall(vim.fn.jobstart, "text", { term = true })
    check(
        "SHELL-invalid-executable-no-child",
        { success, #vim.fn.glob(root .. "/native-*.json", false, true) == before_files },
        { false, true }
    )
    vim.o.shell = "/bin/sh"
    vim.o.shellquote = ""
    local literal = {
        "",
        "%",
        "#",
        "$PROBE_VALUE",
        "~",
        "a b",
        "'\"\\",
        "|",
        ";",
        "#{pane_id}",
        "#(false)",
        "\n",
    }
    check("JOB-direct-argv-literals", job(vim.list_extend({ fixture }, literal)).argv, literal)
    -- Actual shell demonstrates why :S matters (same synthetic filename).
    check(
        "EX-unescaped-filename-negative-control",
        ex(vim.fn.shellescape(fixture) .. " %").argv,
        { root .. "/current", "file.txt" }
    )
    check(
        "EX-escaped-filename-real-shell",
        ex(vim.fn.shellescape(fixture) .. " %:S").argv,
        { root .. "/current file.txt" }
    )
    local piped = ex("printf 'synthetic-pipe\\n' | PROBE_READ=1 " .. vim.fn.shellescape(fixture))
    check("EX-real-pipeline", piped.input, "synthetic-pipe")
    vim.env.PROBE_VALUE = "synthetic-shell-expansion"
    check(
        "EX-real-shell-variable-tilde",
        ex(vim.fn.shellescape(fixture) .. ' "$PROBE_VALUE" ~').argv,
        { "synthetic-shell-expansion", root .. "/home" }
    )
    -- Capture effective cwd in the invoking window, not after a new placement.
    fresh()
    vim.cmd("cd " .. vim.fn.fnameescape(root .. "/global"))
    check("CWD-cd", job({ fixture }).cwd, root .. "/global")
    vim.cmd("tcd " .. vim.fn.fnameescape(root .. "/tab"))
    check("CWD-tcd", job({ fixture }).cwd, root .. "/tab")
    vim.cmd("lcd " .. vim.fn.fnameescape(root .. "/window"))
    check("CWD-lcd", job({ fixture }).cwd, root .. "/window")
    check("CWD-explicit", job({ fixture }, { cwd = root .. "/explicit" }).cwd, root .. "/explicit")
    fresh()
    before = opened
    success = pcall(vim.fn.jobstart, { fixture }, { term = true, cwd = root .. "/missing" })
    check("CWD-invalid-no-terminal", { success, opened == before }, { false, true })
    vim.env.PROBE_VALUE = "fresh-invoker"
    vim.env.PROBE_KEEP = "keep"
    vim.env.PROBE_DROP = "drop"
    vim.env.TMUX = "synthetic-outer"
    vim.env.TMUX_PANE = "%999"
    local inherited = job({ fixture }, { env = { PROBE_VALUE = "override" } })
    check("ENV-invoker-override-routing-not-stripped", {
        inherited.env.PROBE_VALUE,
        inherited.env.PROBE_KEEP,
        inherited.env.TMUX,
        inherited.env.TMUX_PANE,
        inherited.env.TERM,
        inherited.nvim_present,
    }, { "override", "keep", "synthetic-outer", "%999", "xterm-256color", true })
    local out = outpath()
    fresh()
    local id = vim.fn.jobstart({ fixture }, {
        term = true,
        clear_env = true,
        env = { PROBE_OUT = out, PROBE_VALUE = "only", NVIM = "synthetic-override" },
    })
    local cleared = collect(out, id)
    check(
        "ENV-clear-env",
        { cleared.env, cleared.nvim_present },
        { { PROBE_VALUE = "only", TERM = "xterm-256color" }, true }
    )
    -- Child readiness is the barrier; never sleep and hope input has started.
    out = outpath()
    fresh()
    id = vim.fn.jobstart({ fixture }, { term = true, env = { PROBE_READ = "1" } })
    assert(vim.wait(3000, function()
        return vim.fn.filereadable((out:gsub("%.json$", ".ready"))) == 1
    end, 5))
    vim.fn.chansend(id, "synthetic-input\n")
    local pty = collect(out, id)
    check(
        "PTY-child-tty-and-channel-input",
        { pty.tty, pty.input },
        { { true, true, true }, "synthetic-input" }
    )
    -- Real interactive shell omission vs empty command text.
    fresh()
    vim.env.PROBE_OUT = root .. "/shell-input.json"
    vim.cmd("terminal")
    id = vim.b.terminal_job_id
    vim.fn.chansend(id, vim.fn.shellescape(fixture) .. "\nexit\n")
    check("PTY-real-interactive-shell", collect(vim.env.PROBE_OUT, id).tty, { true, true, true })
    fresh()
    id = vim.fn.jobstart("", { term = true })
    check("PTY-empty-command-exits", vim.fn.jobwait({ id }, 3000), { 0 })
    -- Native :terminal replaces current buffer; it is not Sess's tab-default policy.
    fresh()
    local tabs, wins = #vim.api.nvim_list_tabpages(), #vim.api.nvim_list_wins()
    out = outpath()
    vim.cmd("terminal " .. vim.fn.shellescape(fixture))
    collect(out, vim.b.terminal_job_id)
    check(
        "VIEW-native-current-normal-mode",
        { #vim.api.nvim_list_tabpages(), #vim.api.nvim_list_wins(), vim.api.nvim_get_mode().mode },
        { tabs, wins, "nt" }
    )
    for _, right in ipairs({ false, true }) do
        fresh()
        vim.o.splitright = right
        local old = vim.api.nvim_get_current_win()
        out = outpath()
        vim.cmd("vertical terminal " .. vim.fn.shellescape(fixture))
        collect(out, vim.b.terminal_job_id)
        local new = vim.api.nvim_get_current_win()
        check(
            "VIEW-vertical-splitright-" .. tostring(right),
            vim.fn.win_screenpos(new)[2] > vim.fn.win_screenpos(old)[2],
            right
        )
    end
    for _, below in ipairs({ false, true }) do
        fresh()
        vim.o.splitbelow = below
        local old = vim.api.nvim_get_current_win()
        out = outpath()
        vim.cmd("horizontal terminal " .. vim.fn.shellescape(fixture))
        collect(out, vim.b.terminal_job_id)
        local new = vim.api.nvim_get_current_win()
        check(
            "VIEW-horizontal-splitbelow-" .. tostring(below),
            vim.fn.win_screenpos(new)[1] > vim.fn.win_screenpos(old)[1],
            below
        )
    end
    fresh()
    tabs = #vim.api.nvim_list_tabpages()
    out = outpath()
    vim.cmd("tab terminal " .. vim.fn.shellescape(fixture))
    collect(out, vim.b.terminal_job_id)
    check("VIEW-explicit-tab", #vim.api.nvim_list_tabpages(), tabs + 1)
end)
if not ok then
    results[#results + 1] = { id = "HARNESS", status = "fail", error = tostring(err) }
end
vim.fn.writefile({ vim.json.encode(results) }, root .. "/native-results.json")
vim.cmd("qa!")
