local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local sidebar = require("sess.ui.sidebar")
    vim.o.columns = 200
    sidebar.configure({ refresh_interval = 60000, width = 96, max_width = 96 })

    local function reconnect(item, state, name, owner)
        local content_win = vim.api.nvim_get_current_win()
        local content = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(content, 0, -1, false, { "keep modified " .. name })
        vim.cmd("lcd " .. vim.fn.fnameescape(fixture.directory(name .. "-cwd")))
        local cwd = vim.fn.getcwd()
        for _, mode in ipairs({ "hidden", "wiped" }) do
            -- Neither a live attachment nor completed output is already visible.
            local previous = vim.api.nvim_get_current_buf()
            vim.api.nvim_set_current_buf(content)
            if mode == "wiped" then
                vim.api.nvim_buf_delete(previous, { force = true })
            end
            assert(sidebar.open())
            local sidebar_win = vim.api.nvim_get_current_win()
            local sidebar_buf = vim.api.nvim_get_current_buf()
            local function key(lhs)
                return vim.fn.maparg(lhs, "n", false, true).callback()
            end
            local function select(text, available)
                t.wait_for(function()
                    local lines = vim.api.nvim_buf_get_lines(sidebar_buf, 0, -1, false)
                    if table.concat(lines, "\n"):find("stale", 1, true) then
                        return false
                    end
                    for index, line in ipairs(lines) do
                        if
                            line:find(text, 1, true)
                            and (not available or line:find("available", 1, true))
                        then
                            vim.api.nvim_win_set_cursor(sidebar_win, { index, 0 })
                            vim.api.nvim_exec_autocmds("CursorMoved", { buffer = sidebar_buf })
                            return true
                        end
                    end
                end, "missing sidebar row: " .. text)
            end
            if not item.execution.owner_id then
                select("Background terminals")
                key("<CR>")
            end
            select(item.id, true)
            key("<CR>")
            assert(
                vim.api.nvim_get_current_win() == content_win,
                name
                    .. " "
                    .. mode
                    .. ": focus stayed in "
                    .. vim.api.nvim_get_current_buf()
                    .. " ("
                    .. vim.api.nvim_buf_get_name(0)
                    .. ")"
            )
            local reopened = vim.api.nvim_get_current_buf()
            assert(reopened ~= content and reopened ~= sidebar_buf)
            if state == "running" then
                fixture.equal("terminal", vim.bo[reopened].buftype)
                t.probe({ bufnr = reopened, job_id = vim.b[reopened].terminal_job_id }, name, mode)
            else
                fixture.equal("nofile", vim.bo[reopened].buftype)
                assert(vim.bo[reopened].readonly and not vim.bo[reopened].modifiable)
                assert(vim.b[reopened].terminal_job_id == nil)
                t.output({ bufnr = reopened }, "COMPLETED-" .. name)
                fixture.equal({ "once" }, vim.fn.readfile(fixture.root .. "/" .. name .. ".count"))
            end
            assert(vim.api.nvim_buf_is_valid(content) and vim.bo[content].modified)
            fixture.equal(
                { "keep modified " .. name },
                vim.api.nvim_buf_get_lines(content, 0, -1, false)
            )
            fixture.equal(cwd, vim.fn.getcwd())
            fixture.equal(owner and owner.id or nil, api.state.current() and api.state.current().id)
            fixture.equal(owner and 1 or 0, #api.state.active())
            local ok, err, entries = api.terminal.list()
            assert(ok, err)
            local entry
            for _, candidate in ipairs(entries) do
                if candidate.id == item.id then
                    entry = candidate
                end
            end
            assert(entry and entry.execution_state == state and entry.available)
            fixture.equal(item.execution.owner_id, entry.owner_id)
            assert(sidebar.is_open())
            assert(sidebar.close())
        end
    end

    local owner
    local ownerless
    for _, ownership in ipairs({ "ownerless", "current-owner" }) do
        if ownership == "current-owner" then
            local ok, err
            ok, err, owner = api.session.create(fixture.directory("owner"))
            assert(ok, err)
        end
        local name = ownership .. "-running"
        local running = t.launch(t.probe_command(name))
        t.output(running, "READY-" .. name)
        reconnect(running, "running", name, owner)
        ownerless = ownerless or running
        name = ownership .. "-completed"
        local completed = t.launch(
            "printf 'once\\n' >> "
                .. vim.fn.shellescape(fixture.root .. "/" .. name .. ".count")
                .. "; printf 'COMPLETED-"
                .. name
                .. "\\n'"
        )
        t.wait_for(function()
            return t.tmux({
                "display-message",
                "-p",
                "-t",
                completed.execution.pane_id,
                "#{pane_dead}",
            }) == "1\n"
        end)
        reconnect(completed, "completed", name, owner)
    end
    -- Focusing unassigned work from a current session neither switches nor adopts it.
    local ok, err, focused = api.terminal.focus(ownerless.id)
    assert(ok, err)
    reconnect(focused, "running", "ownerless-running", owner)
end)
