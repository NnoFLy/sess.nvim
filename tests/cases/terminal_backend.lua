local backend = require("sess.terminal.backend")
local store = require("sess.terminal.storage")
local storage = require("sess.storage")
local root = fixture.root
local sockets = {}
local tmux = vim.fn.exepath("tmux")
assert(tmux ~= "", "real tmux is required for backend tests")

local function initialize(name)
    assert(storage.init(root .. "/" .. name))
    local paths = assert(store.paths())
    sockets[#sockets + 1] = paths.socket
    return paths
end

local function raw(paths, args)
    local command = { tmux, "-S", paths.socket, "-f", paths.config }
    vim.list_extend(command, args)
    local result = vim.system(command, { env = { TMUX = "", TMUX_PANE = "" }, text = true })
        :wait(3000)
    assert(result.code == 0, result.stderr)
    return result.stdout
end

local function rejects(fn, pattern)
    local item, err = fn()
    assert(not item and type(err) == "string", vim.inspect({ item, err }))
    if pattern then
        assert(err:find(pattern), err)
    end
end

local ok, err = xpcall(function()
    initialize("unused")
    local path = vim.env.PATH
    vim.env.PATH = "/nonexistent"
    assert(backend.can_delete_owner("ordinary"))
    vim.env.PATH = path

    local paths = initialize("backend")
    local cwd = fixture.directory("literal #{pid} #(;)= space")
    rejects(function()
        return backend.create({ cwd = cwd, owner_id = "../bad" })
    end, "invalid session id")
    rejects(function()
        return backend.create({ cwd = "relative" })
    end, "cwd")
    rejects(function()
        return backend.create({ cwd = cwd, command = "a\0b" })
    end, "NUL")
    rejects(function()
        return backend.get("@0; kill-server")
    end, "invalid")
    rejects(function()
        return backend.create({ cwd = cwd, shell = "/bin/sh -c bad" })
    end, "unavailable")

    local execution, create_err = backend.create({
        cwd = cwd,
        owner_id = "project",
        shell = "/bin/sh",
        command = "printf 'cwd=%s\\n' \"$PWD\"; printf '%s\\n' 'quoted | redirect > ;'; printf finished;",
    })
    assert(execution, create_err)
    fixture.equal("project", execution.owner_id)
    assert(vim.wait(2000, function()
        return raw(paths, { "display-message", "-p", "-t", execution.pane_id, "#{pane_dead}" })
            == "1\n"
    end, 20))
    local output = raw(paths, { "capture-pane", "-p", "-J", "-S", "-", "-t", execution.pane_id })
    assert(output:find("cwd=" .. cwd, 1, true), output)
    assert(output:find("quoted | redirect > ;", 1, true), output)
    assert(output:find("finished", 1, true), output)
    local data = assert(store.read())
    assert(not vim.json.encode(data):find("printf", 1, true), "launch text was persisted")
    assert(store.private(paths.socket, "socket"))
    assert(store.private(paths.config, "file"))
    fixture.equal(
        "on\n",
        raw(
            paths,
            { "show-options", "-A", "-w", "-v", "-t", execution.window_id, "remain-on-exit" }
        )
    )
    fixture.equal(
        "off\n",
        raw(paths, { "show-options", "-A", "-v", "-t", execution.session_id, "status" })
    )
    fixture.equal(
        "None\n",
        raw(paths, { "show-options", "-A", "-v", "-t", execution.session_id, "prefix" })
    )
    fixture.equal(
        "off\n",
        raw(paths, { "show-options", "-A", "-v", "-t", execution.session_id, "mouse" })
    )
    rejects(function()
        return backend.can_delete_owner("project")
    end, "deletion refused")
    assert(backend.can_delete_owner("unrelated"))

    -- Fresh editor process validates the same persisted identity; no launch.
    fixture.startup(string.format(
        [[check(function()
        assert(require('sess.storage').init(%q))
        local execution, err = require('sess.terminal.backend').get(%q)
        assert(execution, err)
        assert(execution.window_id == %q)
    end)]],
        storage.root(),
        execution.id,
        execution.window_id
    ))

    local child_file = root .. "/child-execution"
    fixture.startup(string.format(
        [[check(function()
        assert(require('sess.storage').init(%q))
        local item, err = require('sess.terminal.backend').create({cwd=%q, shell='/bin/sh'})
        assert(item, err)
        vim.fn.writefile({item.id}, %q)
    end)]],
        storage.root(),
        cwd,
        child_file
    ))
    local child = assert(backend.get(vim.fn.readfile(child_file)[1]))
    fixture.equal(
        "0\n",
        raw(paths, { "display-message", "-p", "-t", child.pane_id, "#{pane_dead}" })
    )

    local other = assert(
        backend.create({ cwd = cwd, owner_id = "project", command = "sleep 90", shell = "/bin/sh" })
    )
    fixture.equal(execution.session_id, other.session_id)
    assert(execution.window_id ~= other.window_id)
    local unassigned =
        assert(backend.create({ cwd = cwd, command = "sleep 90", shell = "/bin/sh" }))
    assert(unassigned.owner_id == nil and unassigned.session_id ~= execution.session_id)
    assert(backend.can_delete_owner("unrelated"))

    -- A helper placeholder can still be running after new-session returns.
    -- Release a real blocked fixture only after its first verified live query.
    local placeholder = root .. "/delayed-placeholder"
    local release = root .. "/release-placeholder"
    assert(vim.fn.writefile({
        "#!/bin/sh",
        "while [ ! -f " .. vim.fn.shellescape(release) .. " ]; do /bin/sleep 0.01; done",
    }, placeholder) == 0)
    assert(vim.uv.fs_chmod(placeholder, 448))
    local exepath, system = vim.fn.exepath, vim.system
    local saw_live, saw_dead, kill_target = false, false, nil
    vim.fn.exepath = function(name)
        return name == "true" and placeholder or exepath(name)
    end
    vim.system = function(command, options)
        if
            vim.tbl_contains(
                command,
                "#{session_id}\t#{session_name}\t#{@sess_helper}\t#{window_id}\t#{pane_dead}"
            )
        then
            local collect, output = options.stdout, ""
            options.stdout = function(read_err, chunk)
                output = output .. (chunk or "")
                if output:match("\t0\n$") and not saw_live then
                    saw_live = true
                    vim.schedule(function()
                        assert(vim.fn.writefile({}, release) == 0)
                    end)
                elseif output:match("\t1\n$") then
                    saw_dead = true
                end
                collect(read_err, chunk)
            end
        elseif vim.tbl_contains(command, "unlink-window") then
            assert(saw_live and saw_dead, "placeholder unlinked before verified exit")
        elseif vim.tbl_contains(command, "kill-session") then
            kill_target = command[#command]
        end
        return system(command, options)
    end
    local delayed_ok, delayed_err = xpcall(function()
        local delayed, delayed_failure = backend.prepare_attachment(execution.id)
        assert(delayed, delayed_failure)
        assert(saw_live and saw_dead)
        assert(backend.cleanup_attachment(delayed))
        fixture.equal("=sess_h_" .. delayed.helper_id, kill_target)
    end, debug.traceback)
    vim.fn.exepath, vim.system = exepath, system
    assert(delayed_ok, delayed_err)

    local view1, view_err = backend.prepare_attachment(execution.id)
    assert(view1, view_err)
    local view2 = assert(backend.prepare_attachment(other.id))
    fixture.equal("", view1.env.TMUX)
    assert(view1.session_id ~= view2.session_id)
    fixture.equal(
        execution.window_id .. "\n",
        raw(paths, { "list-windows", "-t", view1.session_id, "-F", "#{window_id}" })
    )
    fixture.equal(
        other.window_id .. "\n",
        raw(paths, { "list-windows", "-t", view2.session_id, "-F", "#{window_id}" })
    )
    local process_before =
        raw(paths, { "display-message", "-p", "-t", other.pane_id, "#{pane_pid}" })
    local terminal_buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(terminal_buffer)
    local tmux_env = vim.env.TMUX
    vim.env.TMUX = "unrelated-nested-server,1,0"
    local job = vim.fn.jobstart(view2.argv, { term = true, env = view2.env })
    vim.env.TMUX = tmux_env
    assert(job > 0)
    assert(vim.wait(2000, function()
        return raw(
            paths,
            { "display-message", "-p", "-t", view2.session_id, "#{session_attached}" }
        ) == "1\n"
    end, 20))
    vim.api.nvim_buf_delete(terminal_buffer, { force = true })
    assert(backend.get(other.id))
    fixture.equal(
        process_before,
        raw(paths, { "display-message", "-p", "-t", other.pane_id, "#{pane_pid}" })
    )
    assert(backend.cleanup_attachment(view1))
    assert(backend.get(execution.id))
    assert(backend.get(other.id))
    assert(backend.cleanup_attachment(view2))
    rejects(function()
        return backend.cleanup_attachment(view2)
    end)
    local forged = vim.deepcopy(view1)
    forged.session_id = execution.session_id
    rejects(function()
        return backend.cleanup_attachment(forged)
    end, "identity mismatch")
    assert(backend.get(execution.id))

    raw(paths, { "set-option", "-p", "-t", execution.pane_id, "@sess_pane_token", "reused" })
    rejects(function()
        return backend.get(execution.id)
    end, "identity mismatch")
    assert(backend.can_delete_owner("unrelated"))
    rejects(function()
        return backend.can_delete_owner("project")
    end, "deletion refused")
    raw(paths, { "set-option", "-p", "-t", execution.pane_id, "@sess_pane_token", execution.token })
    assert(backend.get(execution.id))

    -- Unknown live work still protects its actual owner, not unrelated sessions.
    local unknown = raw(paths, {
        "new-window",
        "-d",
        "-P",
        "-F",
        "#{window_id}",
        "-t",
        other.session_id,
        "/bin/sleep",
        "90",
    }):gsub("\n$", "")
    assert(backend.can_delete_owner("unrelated"))
    rejects(function()
        return backend.can_delete_owner("project")
    end, "deletion refused")
    raw(paths, { "kill-window", "-t", unknown })

    local rename_before = vim.uv.fs_rename
    vim.uv.fs_rename = function(source, destination)
        if destination == paths.registry then
            return nil, "injected reservation failure"
        end
        return rename_before(source, destination)
    end
    local windows_before = raw(paths, { "list-windows", "-a", "-F", "#{window_id}" })
    local no_launch, reservation_err = backend.create({
        cwd = cwd,
        owner_id = "not-launched",
        command = "sleep 90",
        shell = "/bin/sh",
    })
    vim.uv.fs_rename = rename_before
    assert(not no_launch and reservation_err:find("publication failed"), reservation_err)
    fixture.equal(windows_before, raw(paths, { "list-windows", "-a", "-F", "#{window_id}" }))

    -- Even a helper with the only surviving link must not be cleaned up:
    -- doing so would destroy execution after external owner-window removal.
    local sole_view = assert(backend.prepare_attachment(child.id))
    raw(paths, { "unlink-window", "-k", "-t", child.session_id .. ":" .. child.window_id })
    rejects(function()
        return backend.cleanup_attachment(sole_view)
    end, "without verified owning window")
    fixture.equal(
        "0\n",
        raw(paths, { "display-message", "-p", "-t", child.pane_id, "#{pane_dead}" })
    )

    -- A post-launch registry publication failure retains both work and a
    -- pending association. It is never returned as an ordinary terminal.
    local rename = vim.uv.fs_rename
    local calls = 0
    vim.uv.fs_rename = function(source, destination)
        if destination == paths.registry then
            calls = calls + 1
            if calls == 2 then
                return nil, "injected final publication failure"
            end
        end
        return rename(source, destination)
    end
    local failed, persistence_err =
        backend.create({ cwd = cwd, owner_id = "failure", command = "sleep 90", shell = "/bin/sh" })
    vim.uv.fs_rename = rename
    assert(not failed and persistence_err:find("persistence failed"), persistence_err)
    rejects(function()
        return backend.can_delete_owner("failure")
    end, "deletion refused")
    local after = assert(store.read())
    local pending = false
    for _, record in pairs(after.executions) do
        pending = pending or record.phase == "pending"
    end
    assert(pending)

    local original_registry = vim.fn.readfile(paths.registry)
    local forged_registry = assert(store.read())
    forged_registry.owners[execution.owner_key].owner_id = "forged"
    forged_registry.executions[execution.id].owner_id = "forged"
    assert(vim.fn.writefile({ vim.json.encode(forged_registry) }, paths.registry) == 0)
    rejects(function()
        return backend.can_delete_owner("project")
    end, "invalid terminal owner association")
    assert(vim.fn.writefile(original_registry, paths.registry) == 0)

    -- Static symlinks are rejected rather than read, chmodded, or replaced.
    assert(vim.uv.fs_rename(paths.config, paths.config .. ".saved"))
    assert(vim.uv.fs_symlink(paths.config .. ".saved", paths.config))
    rejects(function()
        return backend.get(execution.id)
    end, "untrusted")
    assert(vim.uv.fs_lstat(paths.config).type == "link")
    assert(vim.uv.fs_unlink(paths.config))
    assert(vim.uv.fs_rename(paths.config .. ".saved", paths.config))

    -- Malformed metadata is preserved, not repaired by create/deletion checks.
    assert(vim.fn.writefile({ "{corrupt" }, paths.registry) == 0)
    local corrupt = table.concat(vim.fn.readfile(paths.registry), "\n")
    rejects(function()
        return backend.can_delete_owner("unrelated")
    end, "corrupt")
    rejects(function()
        return backend.create({ cwd = cwd })
    end, "corrupt")
    fixture.equal(corrupt, table.concat(vim.fn.readfile(paths.registry), "\n"))

    initialize("missing")
    vim.env.PATH = "/nonexistent"
    rejects(function()
        return backend.create({ cwd = cwd, shell = "/bin/sh" })
    end, "tmux is unavailable")
    assert(backend.can_delete_owner("unrelated"))
    vim.env.PATH = path
    assert(backend.can_delete_owner("unrelated"))

    -- Unassigned work on an unavailable server does not own unrelated sessions.
    local lost = initialize("lost-unassigned")
    assert(backend.create({ cwd = cwd, shell = "/bin/sh", command = "sleep 90" }))
    raw(lost, { "kill-server" })
    assert(backend.can_delete_owner("unrelated"))

    -- A saved attachment argv must not target a recycled numeric session ID.
    local recycled = initialize("recycled-helper")
    local original = assert(backend.create({ cwd = cwd, shell = "/bin/sh", command = "sleep 90" }))
    local attachment = assert(backend.prepare_attachment(original.id))
    fixture.equal("=sess_h_" .. attachment.helper_id, attachment.argv[#attachment.argv])
    raw(recycled, { "kill-server" })
    assert(vim.wait(1000, function()
        return vim.system({ tmux, "-S", recycled.socket, "list-sessions" }):wait(1000).code ~= 0
    end, 10))
    local reused
    for index = 0, tonumber(attachment.session_id:sub(2)) do
        reused = raw(recycled, {
            "new-session",
            "-d",
            "-P",
            "-F",
            "#{session_id}",
            "-s",
            "unrelated-" .. index,
            "--",
            "/bin/sleep",
            "90",
        }):gsub("\n$", "")
    end
    fixture.equal(attachment.session_id, reused)
    local stale_buffer = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(stale_buffer)
    local stale_job = vim.fn.jobstart(attachment.argv, { term = true, env = attachment.env })
    assert(stale_job > 0)
    assert(
        vim.wait(2000, function()
            return vim.fn.jobwait({ stale_job }, 0)[1] ~= -1
        end, 20),
        "saved attachment attached an unrelated replacement session"
    )
    fixture.equal("", raw(recycled, { "list-clients", "-F", "#{client_session}" }))
    vim.api.nvim_buf_delete(stale_buffer, { force = true })

    local bin = fixture.directory("bin")
    local fake = bin .. "/tmux"
    assert(vim.fn.writefile({ "#!/bin/sh", "exec /bin/sleep 20" }, fake) == 0)
    assert(vim.uv.fs_chmod(fake, 448))
    initialize("timeout")
    vim.env.PATH = bin
    local started = vim.uv.hrtime()
    rejects(function()
        return backend.create({ cwd = cwd, shell = "/bin/sh" })
    end, "tmux failed")
    assert((vim.uv.hrtime() - started) / 1e9 < 6, "subprocess wait was not bounded")
    vim.env.PATH = path
    local head = vim.fn.exepath("head")
    assert(head ~= "")
    assert(
        vim.fn.writefile(
            { "#!/bin/sh", "exec " .. vim.fn.shellescape(head) .. " -c 262144 /dev/zero" },
            fake
        ) == 0
    )
    initialize("output-limit")
    vim.env.PATH = bin
    rejects(function()
        return backend.create({ cwd = cwd, shell = "/bin/sh" })
    end, "output exceeded limit")
    vim.env.PATH = path
end, debug.traceback)

for _, socket in ipairs(sockets) do
    -- The test never targets the default/user server, even on failure.
    vim.system({ tmux, "-S", socket, "kill-server" }, { env = { TMUX = "", TMUX_PANE = "" } })
        :wait(3000)
end
assert(ok, err)
