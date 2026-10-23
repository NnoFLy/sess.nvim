local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    for _, kind in ipairs({ "terminal", "nofile" }) do
        local original = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(original)
        local job
        if kind == "terminal" then
            job = vim.fn.jobstart({ "/bin/sh", "-c", "exec sleep 60" }, { term = true })
            assert(job > 0)
        else
            vim.bo[original].buftype = "nofile"
            vim.api.nvim_buf_set_lines(original, 0, -1, false, { "keep non-file content" })
            vim.bo[original].modified = false
        end
        vim.bo[original].bufhidden = "wipe"
        local item = t.launch(t.probe_command("from-" .. kind))
        assert(vim.api.nvim_buf_is_valid(original), "launch wiped original " .. kind .. " buffer")
        fixture.equal(kind, vim.bo[original].buftype)
        if job then
            fixture.equal(-1, vim.fn.jobwait({ job }, 0)[1])
        else
            fixture.equal(
                { "keep non-file content" },
                vim.api.nvim_buf_get_lines(original, 0, -1, false)
            )
        end
        t.probe(item, "from-" .. kind, "source-preserved")
    end
end)
