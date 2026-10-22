local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
local hook_runs, cancel = 0, false
terminal.run(function(t)
    local api = require("sess.api")
    local _, _, owner = api.session.create(fixture.directory("owner"))
    local first = t.launch(t.probe_command("safe-focus"))
    t.output(first, "READY-safe-focus")
    assert(api.session.unload(owner.id))
    local _, _, other = api.session.create(fixture.directory("other"))
    local current_buf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(current_buf, 0, -1, false, { "keep unsaved" })
    cancel = true
    local ok, err = api.terminal.focus(first.id)
    assert(not ok and err:find("cancel terminal owner load", 1, true), err)
    fixture.equal(1, hook_runs)
    fixture.equal(other.id, api.state.current().id)
    fixture.equal(current_buf, vim.api.nvim_get_current_buf())
    fixture.equal({ "keep unsaved" }, vim.api.nvim_buf_get_lines(current_buf, 0, -1, false))
    t.tmux({ "set-option", "-p", "-t", first.execution.pane_id, "@sess_pane_token", "reused" })
    ok, err = api.terminal.focus(first.id)
    assert(not ok and err:find("identity mismatch", 1, true), err)
    fixture.equal(1, hook_runs) -- validation must precede even a cancelled owner load.
    fixture.equal(other.id, api.state.current().id)
    t.tmux({
        "set-option",
        "-p",
        "-t",
        first.execution.pane_id,
        "@sess_pane_token",
        first.execution.token,
    })
    assert(not api.terminal.focus("@0; kill-server"))
    assert(not api.terminal.focus(first.id, {}))
    cancel = false
    local snapshot = assert(require("sess.storage").get_session_path(owner.id))
    local bytes = t.read(snapshot)
    vim.fn.writefile({ "not a session snapshot" }, snapshot)
    ok, err = api.terminal.focus(first.id)
    assert(not ok, "ordinary snapshot validation must reject a broken owner")
    fixture.equal(other.id, api.state.current().id)
    vim.fn.writefile(vim.split(bytes, "\n", { plain = true }), snapshot)
end, {
    hooks = {
        before_transition = function()
            if cancel then
                hook_runs = hook_runs + 1
                error("cancel terminal owner load")
            end
        end,
    },
})
