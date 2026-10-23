local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local function rejects(operation, fragment)
        local ok, err = operation()
        assert(ok == false and type(err) == "string", vim.inspect({ ok, err }))
        assert(err:find(fragment, 1, true), err)
    end
    local function patched(object, key, replacement, test)
        local original = object[key]
        object[key] = replacement
        local ok, err = xpcall(test, debug.traceback)
        object[key] = original
        assert(ok, err)
    end
    local _, _, owner = api.session.create(fixture.directory("owner"))
    local before = vim.api.nvim_list_bufs()
    local path = vim.env.PATH
    patched(vim.env, "PATH", "/nonexistent", function()
        rejects(function()
            return api.terminal.launch("touch should-not-run")
        end, "tmux is unavailable")
    end)
    fixture.equal(path, vim.env.PATH)
    fixture.equal(before, vim.api.nvim_list_bufs())
    fixture.equal(0, vim.fn.filereadable(owner.metadata.cwd .. "/should-not-run"))
    for _, command in ipairs({ false, {}, "a\0b", string.rep("x", 32769) }) do
        rejects(function()
            return api.terminal.launch(command)
        end, "command")
    end
    rejects(function()
        return api.terminal.launch("true", {})
    end, "options are not supported")
    rejects(function()
        return api.terminal.attach("@0; kill-server")
    end, "invalid")
    fixture.equal(before, vim.api.nvim_list_bufs())
    fixture.equal(owner.id, api.state.current().id)

    local original = t.launch(t.probe_command("original"))
    t.output(original, "READY-original")
    local replacement = t.launch(t.probe_command("replacement"))
    t.output(replacement, "READY-replacement")
    -- Fail only backend creation, after a pending association has been published.
    local system = vim.system
    patched(vim, "system", function(argv, options)
        if vim.tbl_contains(argv, "new-window") or vim.tbl_contains(argv, "new-session") then
            error("injected backend creation failure")
        end
        return system(argv, options)
    end, function()
        local buffers = vim.api.nvim_list_bufs()
        rejects(function()
            return api.terminal.launch("touch must-not-launch")
        end, "pending association retained")
        fixture.equal(buffers, vim.api.nvim_list_bufs())
    end)
    fixture.equal(0, vim.fn.filereadable(owner.metadata.cwd .. "/must-not-launch"))

    -- Fail the final atomic registry publication after execution has started.
    local rename = vim.uv.fs_rename
    local publications = 0
    local marker = fixture.root .. "/persistence-executed"
    patched(vim.uv, "fs_rename", function(from, to, ...)
        if to == t.registry then
            publications = publications + 1
            if publications == 2 then
                return nil, "injected registry rename failure"
            end
        end
        return rename(from, to, ...)
    end, function()
        local buffers = vim.api.nvim_list_bufs()
        rejects(function()
            return api.terminal.launch("printf 'once\\n' >> " .. vim.fn.shellescape(marker))
        end, "persistence failed; pending association retained")
        fixture.equal(buffers, vim.api.nvim_list_bufs())
    end)
    t.wait_for(function()
        return vim.fn.filereadable(marker) == 1
    end)
    fixture.equal({ "once" }, vim.fn.readfile(marker))
    local data = vim.json.decode(t.read(t.registry))
    local pending = 0
    for id, record in pairs(data.executions) do
        if record.phase == "pending" then
            pending = pending + 1
            rejects(function()
                return api.terminal.attach(id)
            end, "incomplete")
        end
    end
    fixture.equal(2, pending)
    rejects(function()
        return api.session.delete(owner.id)
    end, "deletion refused")
    t.probe(replacement, "replacement", "after-failures")

    -- Stale references cannot attach to missing or substituted unrelated work.
    t.tmux({ "kill-window", "-t", original.execution.window_id })
    rejects(function()
        return api.terminal.attach(original.id)
    end, "stale or reused target")
    data.executions[original.id].window_id = replacement.execution.window_id
    data.executions[original.id].pane_id = replacement.execution.pane_id
    vim.fn.writefile({ vim.json.encode(data) }, t.registry)
    local reused = t.read(t.registry)
    rejects(function()
        return api.terminal.attach(original.id)
    end, "stale or reused target")
    fixture.equal(reused, t.read(t.registry))
    local safe = t.attach(replacement.id)
    t.probe(safe, "replacement", "not-retargeted")

    -- Corrupt/incompatible data is evidence, not permission to repair or delete.
    for _, bytes in ipairs({ "{broken json", '{"version":999}' }) do
        vim.fn.writefile({ bytes }, t.registry)
        local persisted = t.read(t.registry)
        local buffers = vim.api.nvim_list_bufs()
        rejects(function()
            return api.terminal.attach(replacement.id)
        end, "registry")
        rejects(function()
            return api.terminal.launch("touch corrupt-fallback")
        end, "registry")
        rejects(function()
            return api.session.delete(owner.id)
        end, "registry")
        fixture.equal(persisted, t.read(t.registry))
        fixture.equal(buffers, vim.api.nvim_list_bufs())
        fixture.equal(owner.id, api.state.current().id)
        fixture.equal(0, vim.fn.filereadable(owner.metadata.cwd .. "/corrupt-fallback"))
    end
    local found, failure, preserved_owner = api.session.get_by_id(owner.id)
    assert(found and preserved_owner, failure)
    fixture.equal(owner, preserved_owner)
    fixture.equal(
        "0\n",
        t.tmux({ "display-message", "-p", "-t", replacement.execution.pane_id, "#{pane_dead}" })
    )
end)
