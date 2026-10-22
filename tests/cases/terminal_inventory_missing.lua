local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local path = vim.env.PATH
    vim.env.PATH = "/nonexistent"
    local ok, err, entries = api.terminal.list()
    vim.env.PATH = path
    assert(ok, err)
    fixture.equal({}, entries)
    assert(
        not vim.uv.fs_lstat(vim.fn.fnamemodify(t.registry, ":h")),
        "list must not initialize a backend"
    )
    local item = t.launch(t.probe_command("missing-inventory"))
    t.output(item, "READY-missing-inventory")
    assert(api.terminal.list())
    local dir = vim.fn.fnamemodify(t.registry, ":h")
    assert(vim.uv.fs_rename(dir, dir .. ".saved"))
    local diagnostics
    ok, err, entries, diagnostics = api.terminal.list()
    assert(vim.uv.fs_rename(dir .. ".saved", dir))
    assert(not ok and type(err) == "string")
    fixture.equal(item.id, entries[1].id)
    assert(not entries[1].available and entries[1].execution_state == "unknown")
    assert(#diagnostics > 0)
end)
