local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local item = t.launch(t.probe_command("sidebar-callbacks"))
    t.output(item, "READY-sidebar-callbacks")
    local content_win = vim.api.nvim_get_current_win()
    local content = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(content)
    vim.api.nvim_buf_set_lines(content, 0, -1, false, { "keep callback content" })
    vim.api.nvim_buf_delete(item.bufnr, { force = true })
    vim.o.columns = 200
    local content_cwd = fixture.directory("content-cwd")
    vim.cmd("lcd " .. vim.fn.fnameescape(content_cwd))
    vim.cmd("rightbelow vsplit")
    local other_win = vim.api.nvim_get_current_win()
    local other = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(other)
    local other_cwd = fixture.directory("other-cwd")
    vim.cmd("lcd " .. vim.fn.fnameescape(other_cwd))
    local global_cwd, tab_cwd = vim.fn.getcwd(-1, -1), vim.fn.getcwd(-1, 0)
    local notifications = {}
    vim.notify = function(message)
        notifications[#notifications + 1] = message
    end
    local sidebar = require("sess.ui.sidebar")
    sidebar.configure({ refresh_interval = 60000 })
    local function ready()
        assert(sidebar.open())
        local win
        for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
            if
                vim.api
                    .nvim_buf_get_name(vim.api.nvim_win_get_buf(candidate))
                    :match("Sess Sidebar$")
            then
                win = candidate
            end
        end
        vim.api.nvim_set_current_win(assert(win))
        local buf = vim.api.nvim_win_get_buf(win)
        t.wait_for(function()
            local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
            if table.concat(lines, "\n"):find("stale", 1, true) then
                return false
            end
            for index, line in ipairs(lines) do
                if line:find("running available", 1, true) then
                    vim.api.nvim_win_set_cursor(win, { index, 0 })
                    return true
                end
            end
        end)
        return vim.fn.maparg("<CR>", "n", false, true).callback, win
    end

    local enter, sidebar_win = ready()
    -- The content helper's fallback must never target the transient sidebar.
    vim.w[content_win].sess_transient_ui = true
    vim.w[other_win].sess_transient_ui = true
    enter()
    fixture.equal(sidebar_win, vim.api.nvim_get_current_win())
    fixture.equal(content, vim.api.nvim_win_get_buf(content_win))
    assert(notifications[#notifications]:find("no content window", 1, true))
    vim.w[content_win].sess_transient_ui = nil
    vim.w[other_win].sess_transient_ui = nil

    -- Returning to the same content window is insufficient: the action still
    -- belongs to the closed instance even if its replacement is already open.
    local replaced = false
    vim.api.nvim_create_autocmd("WinEnter", {
        once = true,
        callback = function()
            assert(sidebar.close())
            assert(sidebar.open())
            vim.api.nvim_set_current_win(content_win)
            replaced = true
        end,
    })
    enter()
    assert(replaced and sidebar.is_open())
    fixture.equal(content, vim.api.nvim_get_current_buf())
    assert(vim.bo[content].modified)
    fixture.equal({ "keep callback content" }, vim.api.nvim_buf_get_lines(content, 0, -1, false))

    -- Redirecting WinEnter to a transient window must not invoke public focus.
    enter, sidebar_win = ready()
    vim.api.nvim_create_autocmd("WinEnter", {
        once = true,
        callback = function()
            vim.api.nvim_set_current_win(sidebar_win)
        end,
    })
    enter()
    fixture.equal(sidebar_win, vim.api.nvim_get_current_win())
    fixture.equal(content, vim.api.nvim_win_get_buf(content_win))
    assert(notifications[#notifications]:find("content window changed", 1, true))

    -- A reentrant acceptance cannot steal the pending token; the new instance
    -- can still complete one real reconnect after the cancelled old acceptance.
    local opens = 0
    vim.api.nvim_create_autocmd("TermOpen", {
        callback = function()
            opens = opens + 1
        end,
    })
    vim.api.nvim_create_autocmd("WinEnter", { once = true, callback = enter })
    enter()
    fixture.equal(1, opens)
    fixture.equal(content_win, vim.api.nvim_get_current_win())
    local buf = vim.api.nvim_get_current_buf()
    t.probe(
        { bufnr = buf, job_id = vim.b[buf].terminal_job_id },
        "sidebar-callbacks",
        "after-callbacks"
    )
    assert(api.state.current() == nil and #api.state.active() == 0)
    -- Choosing the existing content target must not rewrite any cwd scope,
    -- even though the sidebar was opened from the other split's local cwd.
    fixture.equal(content_cwd, vim.fn.getcwd(vim.fn.win_id2win(content_win)))
    fixture.equal(other_cwd, vim.fn.getcwd(vim.fn.win_id2win(other_win)))
    fixture.equal(global_cwd, vim.fn.getcwd(-1, -1))
    fixture.equal(tab_cwd, vim.fn.getcwd(-1, 0))
    fixture.equal(other, vim.api.nvim_win_get_buf(other_win))
    local ok, err, focused = api.terminal.focus(item.id)
    assert(ok, err)
    fixture.equal(item.execution.cwd, focused.execution.cwd)
    assert(focused.execution.owner_id == nil)
    assert(sidebar.close())
end)
