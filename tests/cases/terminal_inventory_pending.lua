local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local system = vim.system
    vim.system = function(argv, options)
        if vim.tbl_contains(argv, "new-session") then
            error("injected backend creation failure")
        end
        return system(argv, options)
    end
    local ok, err = api.terminal.launch("touch must-not-replay")
    vim.system = system
    assert(not ok and err:find("pending association retained", 1, true), err)
    local entries, diagnostics
    ok, err, entries, diagnostics = api.terminal.list()
    assert(not ok and err:find("incomplete", 1, true), err)
    fixture.equal(1, #entries)
    assert(
        entries[1].execution_state == "unknown" and not entries[1].available and #diagnostics > 0
    )
    local bytes = t.read(t.registry)
    assert(not api.terminal.focus(entries[1].id))
    fixture.equal(bytes, t.read(t.registry))
    fixture.equal(0, vim.fn.filereadable(fixture.root .. "/must-not-replay"))
end)
