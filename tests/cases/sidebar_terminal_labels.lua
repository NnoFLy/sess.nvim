local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local ok, err, owner = api.session.create(fixture.directory("owner"))
    assert(ok, err)
    local completed = t.launch("printf 'OWNER-LABEL-OUTPUT\\n'")
    t.wait_for(function()
        return t.tmux({ "display-message", "-p", "-t", completed.execution.pane_id, "#{pane_dead}" })
            == "1\n"
    end)
    assert(api.session.rename(owner.id, "Owner\nproject"))
    assert(api.session.unload(owner.id))
    local entries
    ok, err, entries = api.terminal.list()
    assert(ok, err)
    fixture.equal("Owner\nproject", entries[1].owner_name)

    vim.o.columns = 240
    local sidebar = require("sess.ui.sidebar")
    sidebar.configure({ refresh_interval = 60000, width = 120, max_width = 120 })
    assert(sidebar.open())
    local win, buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    t.wait_for(function()
        for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
            if line:find("Background terminals", 1, true) then
                vim.api.nvim_win_set_cursor(win, { index, 0 })
                return true
            end
        end
    end)
    local enter = vim.fn.maparg("<CR>", "n", false, true).callback
    enter()
    local found
    for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
        if line:find(completed.id, 1, true) then
            assert(line:find("Owner project", 1, true), line)
            assert(not line:find("[%c]"), "terminal row must be a single display-safe line")
            vim.api.nvim_win_set_cursor(win, { index, 0 })
            found = true
        end
    end
    assert(found, "wide sidebar must render terminal with newline owner metadata")
    enter()
    fixture.equal(owner.id, api.state.current().id)
    fixture.equal("Owner\nproject", api.state.current().metadata.name)
    t.output({ bufnr = vim.api.nvim_get_current_buf() }, "OWNER-LABEL-OUTPUT")
    assert(sidebar.close())
end)
