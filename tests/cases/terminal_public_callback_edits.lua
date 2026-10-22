local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local edited
    vim.api.nvim_create_autocmd("BufEnter", {
        once = true,
        callback = function(event)
            edited = event.buf
            vim.api.nvim_buf_set_lines(edited, 0, -1, false, { "keep callback edits" })
            error("injected BufEnter failure after editing")
        end,
    })
    local ok, err = api.terminal.launch(t.probe_command("callback"))
    assert(not ok and err:find("survives; attachment failed", 1, true), err)
    assert(edited and vim.api.nvim_buf_is_valid(edited), "failed attachment wiped callback edits")
    fixture.equal({ "keep callback edits" }, vim.api.nvim_buf_get_lines(edited, 0, -1, false))
    assert(vim.bo[edited].modified)
    local id = assert(err:match("execution (%x+) survives"))
    local item = t.attach(id)
    t.probe(item, "callback", "recover-after-callback")
    fixture.equal({ "keep callback edits" }, vim.api.nvim_buf_get_lines(edited, 0, -1, false))
end)
