local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local ok, err, entries, diagnostics = api.terminal.list()
    assert(ok, err)
    fixture.equal({}, entries)
    fixture.equal({}, diagnostics)
    local unassigned = t.launch(t.probe_command("unassigned"))
    t.output(unassigned, "READY-unassigned")
    local _, _, owner = api.session.create(fixture.directory("owner"))
    local completed = t.launch("printf 'RETAINED-INVENTORY\\n'")
    t.wait_for(function()
        return t.tmux({ "display-message", "-p", "-t", completed.execution.pane_id, "#{pane_dead}" })
            == "1\n"
    end)
    assert(api.session.rename(owner.id, "renamed-owner"))
    fixture.startup(string.format(
        [[check(function()
        assert(require('sess').setup({store_path=%q, smart_auto_load='none', auto_save=false}))
        local api = require('sess.api')
        local ok, err, entries, diagnostics = api.terminal.list()
        assert(ok, err)
        assert(#entries == 2 and #diagnostics == 0)
        local by_id = {}
        for _, entry in ipairs(entries) do by_id[entry.id] = entry end
        local owned, unassigned = by_id[%q], by_id[%q]
        assert(owned.owner_id == %q and owned.owner_name == 'renamed-owner')
        assert(owned.execution_state == 'completed' and owned.available)
        assert(unassigned.owner_id == nil and unassigned.execution_state == 'running' and unassigned.available)
        assert(type(owned.name) == 'string' and not owned.name:find('printf', 1, true))
        assert(api.state.current() == nil)
    end)]],
        require("sess.storage").root(),
        completed.id,
        unassigned.id,
        owner.id
    ))
end)
