local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local backend = require("sess.terminal.backend")
    local prepare = backend.prepare_attachment
    backend.prepare_attachment = function(id)
        local attachment, err = prepare(id)
        if attachment then
            attachment.argv = { "/bin/sh", "-c", "exit 42" }
        end
        return attachment, err
    end
    local open = vim.api.nvim_create_autocmd("TermOpen", {
        once = true,
        callback = function()
            -- Drain the injected client's immediate exit before jobstart returns.
            vim.wait(150)
        end,
    })
    local ok, err = api.terminal.launch(t.probe_command("client-exit"))
    backend.prepare_attachment = prepare
    pcall(vim.api.nvim_del_autocmd, open)
    assert(not ok, "an already-failed attachment client must not report success")
    assert(err:find("survives; attachment failed", 1, true), err)
    local id = assert(err:match("execution (%x+) survives"))
    local item = t.attach(id)
    t.probe(item, "client-exit", "recover-after-client-exit")

    -- Fail a client only after a successful API return; this is an attachment
    -- warning, not execution completion. An intentional wipe stays quiet.
    local log = require("sess.log")
    local warn, warnings = log.warn, {}
    log.warn = function(message)
        warnings[#warnings + 1] = message
    end
    local checked, failure = xpcall(function()
        local deliberate = t.attach(id)
        vim.api.nvim_buf_delete(deliberate.bufnr, { force = true })
        t.wait_for(function()
            return vim.fn.jobwait({ deliberate.job_id }, 0)[1] ~= -1
        end)
        vim.wait(0)
        fixture.equal({}, warnings)
        local release = fixture.root .. "/release-client"
        backend.prepare_attachment = function(execution_id)
            local attachment, prepare_err = prepare(execution_id)
            if attachment then
                attachment.argv = {
                    "/bin/sh",
                    "-c",
                    "while [ ! -f "
                        .. vim.fn.shellescape(release)
                        .. " ]; do /bin/sleep 0.01; done; exit 43",
                }
            end
            return attachment, prepare_err
        end
        local late = t.launch(t.probe_command("late-client"))
        backend.prepare_attachment = prepare
        assert(vim.fn.writefile({}, release) == 0)
        t.wait_for(function()
            return #warnings == 1
        end, "late attachment failure was not reported")
        assert(warnings[1]:find("exit 43", 1, true), warnings[1])
        assert(warnings[1]:find(late.id, 1, true), warnings[1])
        local recovered = t.attach(late.id)
        t.probe(recovered, "late-client", "after-late-client-failure")
    end, debug.traceback)
    backend.prepare_attachment, log.warn = prepare, warn
    assert(checked, failure)
end)
