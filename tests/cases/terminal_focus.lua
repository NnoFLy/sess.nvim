local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local unassigned = t.launch(t.probe_command("focus-unassigned"))
    t.output(unassigned, "READY-focus-unassigned")
    local _, _, owner = api.session.create(fixture.directory("owner"))
    local count = fixture.root .. "/completed-count"
    local completed = t.launch(
        "printf 'once\\n' >> " .. vim.fn.shellescape(count) .. "; printf 'COMPLETED-FOCUS\\n'"
    )
    t.wait_for(function()
        return t.tmux({ "display-message", "-p", "-t", completed.execution.pane_id, "#{pane_dead}" })
            == "1\n"
    end)
    assert(api.session.save())
    fixture.startup(
        string.format(
            [[vim.schedule(function() check(function()
        local loads = 0
        local api = require('sess.api')
        assert(require('sess').setup({store_path=%q, smart_auto_load='none', auto_save=false,
            hooks={before_transition=function(event)
                loads = loads + 1
                local ok, err = api.terminal.focus(%q)
                assert(not ok and err:find('in progress', 1, true))
            end, after_operation=function(event)
                if event.operation == 'load' then error('focus owner diagnostic') end
            end}}))
        local ok, err, item, diagnostics = api.terminal.focus(%q)
        assert(ok, err)
        assert(loads == 1 and api.state.current().id == %q)
        assert(item.id == %q and #diagnostics == 1 and diagnostics[1]:find('focus owner diagnostic', 1, true))
        assert(item.job_id == nil and vim.bo[item.bufnr].readonly and not vim.bo[item.bufnr].modifiable)
        assert(vim.wait(5000, function()
            return table.concat(vim.api.nvim_buf_get_lines(item.bufnr, 0, -1, false), '\n'):find('COMPLETED-FOCUS', 1, true)
        end, 20), vim.inspect(vim.api.nvim_buf_get_lines(item.bufnr, 0, -1, false)))
        ok, err, item = api.terminal.focus(%q)
        assert(ok, err)
        assert(api.state.current().id == %q and item.execution.owner_id == nil and loads == 1)
    end) end)]],
            require("sess.storage").root(),
            completed.id,
            completed.id,
            owner.id,
            completed.id,
            unassigned.id,
            owner.id
        )
    )
    fixture.equal({ "once" }, vim.fn.readfile(count))
    t.probe(unassigned, "focus-unassigned", "after-fresh-focus")
end)
