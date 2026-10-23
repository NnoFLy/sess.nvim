local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local function redirected(operation)
        local foreign = vim.api.nvim_create_buf(true, false)
        local enter = vim.api.nvim_create_autocmd("BufEnter", {
            once = true,
            callback = function()
                vim.api.nvim_set_current_buf(foreign)
            end,
        })
        local ok, err, item = operation()
        pcall(vim.api.nvim_del_autocmd, enter)
        fixture.equal("", vim.bo[foreign].buftype)
        fixture.equal({ "" }, vim.api.nvim_buf_get_lines(foreign, 0, -1, false))
        if ok then
            assert(item.bufnr ~= foreign)
            fixture.equal("terminal", vim.bo[item.bufnr].buftype)
            fixture.equal(item.bufnr, vim.api.nvim_get_chan_info(item.job_id).buffer)
            return item.id
        end
        assert(err:find("survives; attachment failed", 1, true), err)
        return assert(err:match("execution (%x+) survives"), err)
    end
    local id = redirected(function()
        return api.terminal.launch(t.probe_command("redirected"))
    end)
    local item = t.attach(id)
    t.probe(item, "redirected", "launch-survived")
    fixture.equal(
        id,
        redirected(function()
            return api.terminal.attach(id)
        end)
    )
    item = t.attach(id)
    t.probe(item, "redirected", "attach-survived")

    -- Naming callbacks run after jobstart's initial channel validation.
    local renamed
    vim.api.nvim_create_autocmd("BufFilePost", {
        pattern = "sess-terminal://*",
        once = true,
        callback = function(event)
            renamed = event.buf
            vim.api.nvim_buf_set_name(renamed, "callback-adopted-view")
        end,
    })
    local ok, err = api.terminal.attach(id)
    assert(not ok and err:find("survives; attachment failed", 1, true), err)
    assert(vim.api.nvim_buf_is_valid(renamed), "callback-adopted buffer was discarded")
    assert(vim.api.nvim_buf_get_name(renamed):find("callback-adopted-view", 1, true))

    -- Transient resume runs after the inner attachment function returns.
    local resume_once = true
    local foreign = vim.api.nvim_create_buf(true, false)
    assert(require("sess.editor").register_transient_owner({
        suspend = function()
            return true
        end,
        resume = function()
            if resume_once then
                resume_once = false
                vim.api.nvim_set_current_buf(foreign)
            end
            return true
        end,
    }))
    ok, err = api.terminal.attach(id)
    assert(not ok and err:find("survives; attachment failed", 1, true), err)
    fixture.equal("", vim.bo[foreign].buftype)
    item = t.attach(id)
    t.probe(item, "redirected", "after-final-callbacks")
end)
