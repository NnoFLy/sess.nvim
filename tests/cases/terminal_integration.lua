local api = require("sess.api")
local backend = require("sess.terminal.backend")
local store = require("sess.terminal.storage")
local view = require("sess.terminal.view")
local editor = require("sess.editor")
local jobs, buffers = {}, {}
local paths
local tmux = vim.fn.exepath("tmux")
assert(tmux ~= "", "real tmux is required for terminal integration tests")

local function raw(args)
    local command = { tmux, "-S", paths.socket, "-f", paths.config }
    vim.list_extend(command, args)
    local result = vim.system(command, { env = { TMUX = "", TMUX_PANE = "" }, text = true })
        :wait(3000)
    assert(result.code == 0, result.stderr)
    return result.stdout
end

local function remember(item)
    buffers[#buffers + 1] = item.bufnr
    jobs[#jobs + 1] = item.job_id
    return item
end

local ok, err = xpcall(function()
    local success, failure = api.terminal.launch()
    assert(not success and failure:find("setup", 1, true))
    fixture.setup()
    paths = assert(store.paths()) -- Register cleanup before the first possible launch.
    require("sess.ui.command").setup()
    vim.o.shell = "/bin/sh"
    for _, bad in ipairs({ {}, false, "bad\0command", string.rep("x", 32769) }) do
        success, failure = api.terminal.launch(bad)
        assert(not success and failure:find("command", 1, true))
    end
    assert(not api.terminal.launch("true", {}))
    assert(not api.terminal.attach("@0; kill-server"))

    -- The real command adapter passes the untouched shell tail, not fargs.
    local cwd = fixture.directory("effective cwd")
    vim.cmd({ cmd = "lcd", args = { cwd } })
    local command = "printf '%s\\n' \"$PWD\" 'quoted | redirect > ;' | cat > output; exec sleep 60"
    local requested
    local create = backend.create
    backend.create = function(options)
        requested = vim.deepcopy(options)
        return create(options)
    end
    vim.cmd("Sess term " .. command)
    backend.create = create
    fixture.equal(command, requested.command)
    fixture.equal(cwd, requested.cwd)
    fixture.equal(nil, requested.owner_id)
    fixture.equal(nil, api.state.current())
    paths = assert(store.paths())
    assert(vim.wait(2000, function()
        return vim.fn.filereadable(cwd .. "/output") == 1
    end, 20))
    fixture.equal({ cwd, "quoted | redirect > ;" }, vim.fn.readfile(cwd .. "/output"))
    local unassigned_buf = vim.api.nvim_get_current_buf()
    local id = assert(vim.api.nvim_buf_get_name(unassigned_buf):match("sess%-terminal://(%x+)/"))
    local execution = assert(backend.get(id))
    local original_pid = raw({ "display-message", "-p", "-t", execution.pane_id, "#{pane_pid}" })
    local unassigned_job = assert(view.identity(unassigned_buf))
    remember({ bufnr = unassigned_buf, job_id = unassigned_job })

    -- An unassigned execution does not protect unrelated session deletion.
    local _, _, unrelated = api.session.create(fixture.directory("unrelated"))
    assert(api.session.delete(unrelated.id))
    assert(backend.get(id))
    local _, _, owner = api.session.create(fixture.directory("owner"))
    local item, diagnostics
    success, failure, item, diagnostics = api.terminal.launch("exec sleep 60")
    assert(success, failure)
    remember(item)
    fixture.equal(owner.id, item.execution.owner_id)
    fixture.equal({}, diagnostics)
    local owned_id = item.id
    local owned_buf = item.bufnr
    local owned_pid = raw({ "display-message", "-p", "-t", item.execution.pane_id, "#{pane_pid}" })
    success, failure = api.session.delete(owner.id, {
        hooks = {
            before_transition = function()
                error("must refuse before hooks")
            end,
        },
    })
    assert(not success and failure:find("deletion refused", 1, true), failure)
    fixture.equal(owner.id, api.state.current().id)
    assert(vim.api.nvim_buf_is_valid(owned_buf))

    -- A second ordinary terminal attachment is a distinct view of the same work.
    success, failure, item = api.terminal.attach(owned_id)
    assert(success, failure)
    remember(item)
    assert(item.bufnr ~= owned_buf and item.job_id ~= jobs[#jobs - 1])
    fixture.equal(
        owned_pid,
        raw({ "display-message", "-p", "-t", item.execution.pane_id, "#{pane_pid}" })
    )
    -- Spoofed buffer variables cannot turn a managed client into an ordinary job.
    vim.b[item.bufnr].terminal_job_id = -99
    assert(view.identity(item.bufnr) == item.job_id)
    vim.cmd("split")
    vim.cmd("close")
    fixture.equal(
        owned_pid,
        raw({ "display-message", "-p", "-t", item.execution.pane_id, "#{pane_pid}" })
    )

    vim.opt.sessionoptions:append("terminal")
    local snapshot = fixture.root .. "/managed.vim"
    assert(editor.write_snapshot(snapshot))
    local content = table.concat(vim.fn.readfile(snapshot), "\n")
    assert(content:find("sess%-terminal://"), content)
    assert(not content:find("term://", 1, true), content)
    assert(not content:find("attach-session", 1, true), content)
    assert(not content:find("sleep 60", 1, true), content)

    success, failure, _, diagnostics = api.session.unload(owner.id, {
        hooks = {
            after_operation = function()
                local nested, nested_err = api.terminal.launch()
                assert(not nested and nested_err:find("in progress", 1, true))
                error("post-unload diagnostic")
            end,
        },
    })
    assert(success, failure)
    assert(diagnostics[#diagnostics]:find("post-unload diagnostic", 1, true))
    assert(not vim.api.nvim_buf_is_valid(owned_buf))
    assert(backend.get(owned_id))
    fixture.equal(
        owned_pid,
        raw({ "display-message", "-p", "-t", item.execution.pane_id, "#{pane_pid}" })
    )

    vim.api.nvim_buf_delete(unassigned_buf, { force = true })
    assert(vim.wait(2000, function()
        return vim.fn.jobwait({ unassigned_job }, 0)[1] ~= -1
    end, 20))
    fixture.equal(
        original_pid,
        raw({ "display-message", "-p", "-t", execution.pane_id, "#{pane_pid}" })
    )
    fixture.startup(string.format(
        [[check(function()
        assert(require('sess').setup({store_path=%q, smart_auto_load='none', auto_save=false}))
        local ok, err = require('sess.api').terminal.attach(%q)
        assert(ok, err)
    end)]],
        require("sess.storage").root(),
        id
    ))
    assert(backend.get(id), "quitting an attached editor must not stop execution")
    fixture.equal(
        original_pid,
        raw({ "display-message", "-p", "-t", execution.pane_id, "#{pane_pid}" })
    )

    -- No arguments starts an interactive shell, not an invented session.
    vim.cmd("Sess term")
    local shell_buf = vim.api.nvim_get_current_buf()
    local shell_id = assert(vim.api.nvim_buf_get_name(shell_buf):match("sess%-terminal://(%x+)/"))
    local shell_execution = assert(backend.get(shell_id))
    fixture.equal(nil, shell_execution.owner_id)
    fixture.equal(nil, api.state.current())
    remember({ bufnr = shell_buf, job_id = assert(view.identity(shell_buf)) })
    fixture.equal(
        "0\n",
        raw({ "display-message", "-p", "-t", shell_execution.pane_id, "#{pane_dead}" })
    )

    -- A committed launch with a failed view is explicitly recoverable by ID.
    local open = view.open
    view.open = function()
        return nil, "injected attachment failure"
    end
    success, failure = api.terminal.launch("printf completed")
    view.open = open
    assert(not success and failure:find("survives; attachment failed", 1, true), failure)
    local surviving_id = assert(failure:match("execution (%x+) survives"))
    assert(backend.get(surviving_id))

    -- Backend launch failures are surfaced; never substitute a local terminal.
    local path = vim.env.PATH
    local before = vim.api.nvim_list_bufs()
    vim.env.PATH = "/nonexistent"
    success, failure = api.terminal.launch("true")
    vim.env.PATH = path
    assert(not success and failure:find("tmux is unavailable", 1, true), failure)
    fixture.equal(before, vim.api.nvim_list_bufs())

    -- Ordinary jobs still require Stop, even with a forged managed-looking name.
    local _, _, ordinary_owner = api.session.create(fixture.directory("ordinary"))
    local ordinary_buf = vim.api.nvim_get_current_buf()
    local ordinary_job = vim.fn.jobstart({ "/bin/sh", "-c", "exec sleep 60" }, { term = true })
    jobs[#jobs + 1] = ordinary_job
    buffers[#buffers + 1] = ordinary_buf
    local ordinary_snapshot = fixture.root .. "/ordinary.vim"
    assert(editor.write_snapshot(ordinary_snapshot))
    local ordinary_content = table.concat(vim.fn.readfile(ordinary_snapshot), "\n")
    assert(ordinary_content:find("term://", 1, true), "ordinary terminal snapshot behavior changed")
    vim.api.nvim_buf_set_name(ordinary_buf, "sess-terminal://" .. id .. "/forged")
    assert(not view.identity(ordinary_buf))
    success, failure = api.session.unload(ordinary_owner.id)
    assert(not success and failure:find("running terminal jobs", 1, true), failure)
    assert(vim.fn.jobwait({ ordinary_job }, 0)[1] == -1)
    assert(api.session.unload(ordinary_owner.id, {
        confirm = function(request)
            fixture.equal("jobs", request.kind)
            return "stop"
        end,
    }))
end, debug.traceback)

-- Stop clients first so helper cleanup runs against this test's private server.
for _, buf in ipairs(buffers) do
    if vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
end
for _, job in ipairs(jobs) do
    pcall(vim.fn.jobstop, job)
end
vim.wait(1000, function()
    for _, job in ipairs(jobs) do
        if vim.fn.jobwait({ job }, 0)[1] == -1 then
            return false
        end
    end
    return true
end, 10)
vim.wait(0)
if paths then
    vim.system({ tmux, "-S", paths.socket, "kill-server" }):wait(3000)
end
assert(ok, err)
