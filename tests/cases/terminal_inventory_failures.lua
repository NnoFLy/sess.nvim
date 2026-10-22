local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local item = t.launch(t.probe_command("inventory"))
    t.output(item, "READY-inventory")
    local ok, err, entries = api.terminal.list()
    assert(ok, err)
    fixture.equal(1, #entries)
    entries[1].name = "caller mutation"
    local original = t.read(t.registry)
    vim.fn.writefile({ "{corrupt" }, t.registry)
    local diagnostics
    ok, err, entries, diagnostics = api.terminal.list()
    assert(not ok and err:find("corrupt", 1, true), err)
    fixture.equal(1, #entries)
    fixture.equal(item.id, entries[1].id)
    assert(entries[1].name ~= "caller mutation")
    assert(not entries[1].available and entries[1].execution_state == "unknown")
    assert(#diagnostics > 0)
    fixture.equal("{corrupt", t.read(t.registry))
    vim.fn.writefile({ original }, t.registry)
    ok, err, entries = api.terminal.list()
    assert(ok and entries[1].available, err)
    local path = vim.env.PATH
    vim.env.PATH = "/nonexistent"
    ok, err, entries, diagnostics = api.terminal.list()
    vim.env.PATH = path
    assert(not ok and err:find("tmux is unavailable", 1, true), err)
    fixture.equal(item.id, entries[1].id)
    assert(
        not entries[1].available and entries[1].execution_state == "unknown" and #diagnostics > 0
    )
    fixture.equal(original, t.read(t.registry))
    t.probe(item, "inventory", "query-did-not-stop-work")
end)
