local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local first = t.launch(t.probe_command("validated"))
    t.output(first, "READY-validated")
    local second = t.launch(t.probe_command("untouched"))
    t.output(second, "READY-untouched")
    local registry = t.read(t.registry)
    local data = vim.json.decode(registry)
    local owner = data.owners[first.execution.owner_key]
    local markers = {
        { "-s", nil, "@sess_backend", first.execution.backend_id, false },
        { nil, first.execution.session_id, "@sess_owner_token", owner.token, false },
        { "-w", first.execution.window_id, "@sess_window_token", first.execution.token, true },
        { "-p", first.execution.pane_id, "@sess_pane_token", first.execution.token, true },
    }
    for _, marker in ipairs(markers) do
        local function set(value)
            local args = { "set-option" }
            if marker[1] then
                args[#args + 1] = marker[1]
            end
            if marker[2] then
                vim.list_extend(args, { "-t", marker[2] })
            end
            vim.list_extend(args, { marker[3], value })
            t.tmux(args)
        end
        set("unrelated")
        local ok, err, entries, diagnostics = api.terminal.list()
        assert(not ok and type(err) == "string" and #diagnostics > 0)
        fixture.equal(2, #entries)
        local by_id = {}
        for _, entry in ipairs(entries) do
            by_id[entry.id] = entry
        end
        assert(not by_id[first.id].available and by_id[first.id].execution_state == "unknown")
        fixture.equal(marker[5], by_id[second.id].available)
        assert(not api.terminal.focus(first.id))
        fixture.equal(registry, t.read(t.registry))
        set(marker[4])
        assert(api.terminal.list())
    end
    -- A missing target is uncertainty, not deletion; the other work remains usable.
    t.tmux({ "kill-window", "-t", first.execution.window_id })
    local ok, err, entries = api.terminal.list()
    assert(not ok, err)
    fixture.equal(2, #entries)
    local available = {}
    for _, entry in ipairs(entries) do
        available[entry.id] = entry.available
    end
    assert(not available[first.id] and available[second.id])
    fixture.equal(registry, t.read(t.registry))
    t.probe(second, "untouched", "partial-query")
end)
