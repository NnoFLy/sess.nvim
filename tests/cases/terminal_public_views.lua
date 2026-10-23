local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local ok, err, owner = api.session.create(fixture.directory("owner"))
    assert(ok, err)
    local first = t.launch(t.probe_command("first"))
    t.output(first, "READY-first")
    local first_window = vim.api.nvim_get_current_win()
    vim.cmd("vsplit")
    local second = t.launch(t.probe_command("second"))
    t.output(second, "READY-second")
    local second_window = vim.api.nvim_get_current_win()
    assert(first.id ~= second.id and first.execution.pane_id ~= second.execution.pane_id)
    fixture.equal(owner.id, first.execution.owner_id)
    fixture.equal(first.execution.session_id, second.execution.session_id)
    assert(t.pid(first) ~= t.pid(second))
    local first_pid, second_pid = t.pid(first), t.pid(second)

    -- A remote owner selection cannot move either visible one-window attachment.
    for index, item in ipairs({ second, first, second }) do
        t.tmux({
            "select-window",
            "-t",
            item.execution.session_id .. ":" .. item.execution.window_id,
        })
        t.probe(first, "first", "selected-" .. index)
        t.probe(second, "second", "selected-" .. index)
    end
    assert(not t.text(first.bufnr):find("READY-second", 1, true))
    assert(not t.text(second.bufnr):find("READY-first", 1, true))
    fixture.equal(first.bufnr, vim.api.nvim_win_get_buf(first_window))
    fixture.equal(second.bufnr, vim.api.nvim_win_get_buf(second_window))

    vim.cmd("split")
    local repeated = t.attach(first.id)
    assert(repeated.bufnr ~= first.bufnr and repeated.job_id ~= first.job_id)
    fixture.equal(first.execution, repeated.execution)
    t.probe(repeated, "first", "another-view")
    vim.api.nvim_win_close(first_window, false)
    vim.api.nvim_buf_delete(first.bufnr, { force = true })
    t.probe(repeated, "first", "after-close-and-wipe")
    fixture.equal(first_pid, t.pid(repeated))
    fixture.equal(second_pid, t.pid(second))

    -- Reattach completed output without running the command a second time.
    local count = fixture.root .. "/completed.count"
    local completed = t.launch(
        "printf 'launch\\n' >> " .. vim.fn.shellescape(count) .. "; printf 'RETAINED-OUTPUT\\n'"
    )
    t.wait_for(function()
        return t.tmux({ "display-message", "-p", "-t", completed.execution.pane_id, "#{pane_dead}" })
            == "1\n"
    end)
    vim.api.nvim_buf_delete(completed.bufnr, { force = true })
    local recovered = t.attach(completed.id)
    t.output(recovered, "RETAINED-OUTPUT")
    fixture.equal(completed.execution, recovered.execution)
    fixture.equal({ "launch" }, vim.fn.readfile(count))
    local buffers = vim.api.nvim_list_bufs()
    local _, _, owner_before = api.session.get_by_id(owner.id)
    ok, err = api.session.delete(owner.id)
    assert(not ok and err:find("deletion refused", 1, true), err)
    local _, _, owner_after = api.session.get_by_id(owner.id)
    fixture.equal(owner_before, owner_after)
    fixture.equal(buffers, vim.api.nvim_list_bufs())
    fixture.equal(owner.id, api.state.current().id)
    fixture.equal(first_pid, t.pid(repeated))
end)
