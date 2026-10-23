local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local completed = t.launch("printf 'SHORT-COMPLETED\\n'")
    t.wait_for(function()
        return t.tmux({ "display-message", "-p", "-t", completed.execution.pane_id, "#{pane_dead}" })
            == "1\n"
    end)
    local registry = t.read(t.registry)
    local source = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(source)
    vim.bo[source].buftype = "nofile"
    vim.bo[source].bufhidden = "wipe"
    vim.api.nvim_buf_set_lines(source, 0, -1, false, { "keep source content" })
    local ok, err, output = api.terminal.focus(completed.id)
    assert(ok, err)
    assert(vim.api.nvim_buf_is_valid(source))
    fixture.equal({ "keep source content" }, vim.api.nvim_buf_get_lines(source, 0, -1, false))
    assert(
        output.job_id == nil
            and vim.bo[output.bufnr].readonly
            and not vim.bo[output.bufnr].modifiable
    )
    t.output(output, "SHORT-COMPLETED")
    local _, _, repeated = api.terminal.focus(completed.id)
    fixture.equal(output.bufnr, repeated.bufnr)
    -- Buffer-local identity, not a rendered name, determines reuse.
    vim.api.nvim_buf_set_name(output.bufnr, "callback-adopted-output")
    local adopted
    vim.api.nvim_create_autocmd("BufFilePost", {
        pattern = "sess-terminal-output://*",
        once = true,
        callback = function(event)
            adopted = event.buf
            vim.bo[adopted].modifiable = true
            vim.api.nvim_buf_set_lines(adopted, 0, -1, false, { "keep callback output edits" })
        end,
    })
    ok, err = api.terminal.focus(completed.id)
    assert(not ok and err:find("changed before focus", 1, true), err)
    fixture.equal(
        { "keep callback output edits" },
        vim.api.nvim_buf_get_lines(adopted, 0, -1, false)
    )
    ok, err, repeated = api.terminal.focus(completed.id)
    assert(ok and repeated.bufnr ~= adopted and repeated.bufnr ~= output.bufnr, err)
    t.output(repeated, "SHORT-COMPLETED")
    fixture.equal(registry, t.read(t.registry))
    local system = vim.system
    vim.system = function(argv, options)
        local process = system(argv, options)
        if not vim.tbl_contains(argv, "capture-pane") then
            return process
        end
        return {
            kill = function(_, signal)
                return process:kill(signal)
            end,
            wait = function(_, timeout)
                local result = process:wait(timeout)
                t.tmux({
                    "set-option",
                    "-p",
                    "-t",
                    completed.execution.pane_id,
                    "@sess_pane_token",
                    "changed-during-capture",
                })
                return result
            end,
        }
    end
    local before_capture = vim.api.nvim_get_current_buf()
    ok, err = api.terminal.focus(completed.id)
    vim.system = system
    t.tmux({
        "set-option",
        "-p",
        "-t",
        completed.execution.pane_id,
        "@sess_pane_token",
        completed.execution.token,
    })
    assert(not ok and err:find("identity mismatch", 1, true), err)
    fixture.equal(before_capture, vim.api.nvim_get_current_buf())
    -- Capturing too much output fails explicitly, never truncates/replays it.
    local large = t.launch("head -c 100000 /dev/zero | tr '\\000' x")
    t.wait_for(function()
        return t.tmux({ "display-message", "-p", "-t", large.execution.pane_id, "#{pane_dead}" })
            == "1\n"
    end)
    local buf = vim.api.nvim_get_current_buf()
    ok, err = api.terminal.focus(large.id)
    assert(not ok and err:find("output exceeded limit", 1, true), err)
    fixture.equal(buf, vim.api.nvim_get_current_buf())
end)
