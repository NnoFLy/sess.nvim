local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    require("sess.ui.command").setup()
    local ok, err, before = api.session.list()
    assert(ok, err)
    local sentinel = fixture.root .. "/injected"
    local scopes = {
        { "cd", fixture.directory("global #{pid} #(;)= space;") },
        { "tcd", fixture.directory("tab #(touch injected) ' quoted") },
        { "lcd", fixture.directory("window #{session_name} $(touch injected);") },
    }
    for index, scope in ipairs(scopes) do
        vim.api.nvim_cmd(
            { cmd = scope[1], args = { scope[2] }, magic = { file = false, bar = false } },
            {}
        )
        local output = fixture.root .. "/syntax-" .. index
        local command = "printf '%s\\n' \"$PWD\" 'single | > ;' \"double ' quote\" '$(touch "
            .. sentinel
            .. ")' | cat > "
            .. vim.fn.shellescape(output)
        vim.cmd("Sess term " .. command)
        local buf = vim.api.nvim_get_current_buf()
        fixture.equal("terminal", vim.bo[buf].buftype)
        t.wait_for(function()
            return vim.fn.filereadable(output) == 1 and #vim.fn.readfile(output) == 4
        end)
        fixture.equal(
            { scope[2], "single | > ;", "double ' quote", "$(touch " .. sentinel .. ")" },
            vim.fn.readfile(output)
        )
    end
    fixture.equal(0, vim.fn.filereadable(sentinel))
    fixture.equal(0, vim.fn.filereadable(fixture.root .. "/injected"))
    fixture.equal(nil, api.state.current())
    local _, _, after = api.session.list()
    fixture.equal(before, after)

    -- Exercise actual shell input and ordinary terminal output, not just pane liveness.
    vim.cmd("Sess term")
    local buf = vim.api.nvim_get_current_buf()
    local job = vim.b[buf].terminal_job_id
    fixture.equal("terminal", vim.bo[buf].buftype)
    local output = fixture.root .. "/interactive"
    vim.fn.chansend(
        job,
        "printf 'interactive-%s\\n' \"shell\" | tee " .. vim.fn.shellescape(output) .. "\r"
    )
    t.output({ bufnr = buf }, "interactive-shell")
    t.wait_for(function()
        return vim.fn.filereadable(output) == 1
    end)
    fixture.equal({ "interactive-shell" }, vim.fn.readfile(output))
    fixture.equal(nil, api.state.current())
end)
