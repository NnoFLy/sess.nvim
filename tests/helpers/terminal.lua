local M = {}
local tmux = vim.fn.exepath("tmux")
assert(tmux ~= "", "real tmux is required for persistent-terminal public tests")

function M.run(test)
    fixture.setup()
    vim.o.shell = "/bin/sh"
    -- Register the one private socket before any launch, including failed ones.
    local dir = fixture.root .. "/store/terminal"
    local socket = dir .. "/tmux.sock"
    local helper = { socket = socket, registry = dir .. "/registry.json" }
    function helper.tmux(args)
        local command = { tmux, "-S", socket }
        vim.list_extend(command, args)
        local process = vim.system(command, {
            env = { TMUX = "", TMUX_PANE = "" },
            text = true,
        })
        local result = process:wait(3000)
        assert(result.code == 0, (result.stderr or "") .. (result.stdout or ""))
        return result.stdout
    end
    function helper.launch(command)
        local ok, err, item, diagnostics = require("sess.api").terminal.launch(command)
        assert(ok, err)
        assert(item.id == item.execution.id and item.bufnr > 0 and item.job_id > 0)
        fixture.equal("terminal", vim.bo[item.bufnr].buftype)
        assert(type(diagnostics) == "table")
        return item
    end
    function helper.attach(id)
        local ok, err, item, diagnostics = require("sess.api").terminal.attach(id)
        assert(ok, err)
        fixture.equal(id, item.id)
        fixture.equal("terminal", vim.bo[item.bufnr].buftype)
        assert(type(diagnostics) == "table")
        return item
    end
    function helper.text(buf)
        return table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    end
    function helper.wait_for(predicate, message)
        assert(vim.wait(5000, predicate, 20), message or "terminal did not become ready")
    end
    function helper.output(item, text)
        helper.wait_for(function()
            return helper.text(item.bufnr):find(text, 1, true) ~= nil
        end, "missing terminal output: " .. text .. "\n" .. helper.text(item.bufnr))
    end
    function helper.read(path)
        return table.concat(vim.fn.readfile(path), "\n")
    end
    function helper.pid(item)
        return helper.tmux({ "display-message", "-p", "-t", item.execution.pane_id, "#{pane_pid}" })
    end
    function helper.probe_command(name)
        local prefix = vim.fn.shellescape(fixture.root .. "/" .. name)
        return "printf '%s\\n' $$ > "
            .. prefix
            .. ".pid; printf 'launch\\n' >> "
            .. prefix
            .. ".count; printf 'READY-"
            .. name
            .. "\\n'; while IFS= read -r line; do "
            .. "printf '"
            .. name
            .. ':%s:%s\\n\' "$$" "$line"; '
            .. 'printf \'%s:%s\\n\' "$$" "$line" >> '
            .. prefix
            .. ".probes; done"
    end
    function helper.probe(item, name, tag)
        vim.fn.chansend(item.job_id, tag .. "\r")
        local pid = helper.read(fixture.root .. "/" .. name .. ".pid")
        helper.output(item, name .. ":" .. pid .. ":" .. tag)
        helper.wait_for(function()
            local path = fixture.root .. "/" .. name .. ".probes"
            return vim.fn.filereadable(path) == 1
                and helper.read(path):find(pid .. ":" .. tag, 1, true)
        end)
        fixture.equal({ "launch" }, vim.fn.readfile(fixture.root .. "/" .. name .. ".count"))
    end
    local ok, err = xpcall(function()
        test(helper)
    end, function(err)
        return debug.traceback(tostring(err), 2)
    end)
    -- Even assertion failures stop clients and only this case's private server.
    local jobs = {}
    for _, channel in ipairs(vim.api.nvim_list_chans()) do
        if channel.mode == "terminal" then
            jobs[#jobs + 1] = channel.id
            pcall(vim.fn.jobstop, channel.id)
        end
    end
    if #jobs > 0 then
        vim.fn.jobwait(jobs, 1000)
    end
    vim.wait(0)
    vim.system({ tmux, "-S", socket, "kill-server" }, { env = { TMUX = "", TMUX_PANE = "" } })
        :wait(3000)
    assert(ok, err)
end

return M
