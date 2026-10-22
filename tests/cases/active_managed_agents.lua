local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local _, _, session = api.session.create(fixture.directory("project"))
    assert(api.session.load(session.id))
    local item = t.launch("printf 'READY\n'; sleep 60")
    t.output(item, "READY")
    -- Attachment process observations must not manufacture agent identities.
    local original_job_info = vim.fn.job_info
    vim.fn.job_info = function()
        return { status = "run", cmd = { "codex" } }
    end
    local ok, err, agents = api.agent.list(session.id)
    assert(ok, err)
    assert(#agents == 0, "managed terminal views are not automatically derived agents")
    assert(api.agent.register(session.id, {
        id = "explicit",
        name = "codex",
        status = "working",
        bufnr = item.bufnr,
    }))
    local snapshot = api.active.snapshot()
    vim.fn.job_info = original_job_info
    assert(#snapshot.agents_by_id[session.id] == 1)
    assert(snapshot.agents_by_id[session.id][1].id == "explicit")
    assert(#snapshot.terminals == 1 and snapshot.terminals[1].id == item.id)
end)
