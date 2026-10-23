local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local _, _, owner = api.session.create(fixture.directory("owner"))
    local events = 0
    local observer = vim.api.nvim_create_autocmd("User", {
        pattern = "Sess*",
        callback = function()
            events = events + 1
        end,
    })
    local item = t.launch(t.probe_command("safe-unload"))
    t.output(item, "READY-safe-unload")
    local second = t.attach(item.id)
    fixture.equal(0, events)
    vim.api.nvim_del_autocmd(observer)
    local pid = t.pid(item)

    local nonfile = vim.api.nvim_create_buf(true, false)
    vim.bo[nonfile].buftype = "nofile"
    vim.api.nvim_buf_set_lines(nonfile, 0, -1, false, { "non-file content" })
    local modified = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(modified)
    vim.api.nvim_buf_set_lines(modified, 0, -1, false, { "unsaved text" })
    local ok, err = api.session.unload(owner.id)
    assert(not ok and err:find("unsaved buffers", 1, true), tostring(err))
    fixture.equal({ "unsaved text" }, vim.api.nvim_buf_get_lines(modified, 0, -1, false))
    fixture.equal({ "non-file content" }, vim.api.nvim_buf_get_lines(nonfile, 0, -1, false))
    fixture.equal(owner.id, api.state.current().id)
    fixture.equal(pid, t.pid(item))

    local ordinary = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_set_current_buf(ordinary)
    local job = vim.fn.jobstart({ "/bin/sh", "-c", "exec sleep 60" }, { term = true })
    assert(job > 0)
    local requests = {}
    ok, err = api.session.unload(owner.id, {
        hooks = {
            before_transition = function()
                for _, operation in ipairs({
                    function()
                        return api.terminal.launch("touch recursive-launch")
                    end,
                    function()
                        return api.terminal.attach(item.id)
                    end,
                }) do
                    local nested, failure = operation()
                    assert(not nested and failure:find("in progress", 1, true), failure)
                end
            end,
        },
        confirm = function(request)
            requests[#requests + 1] = request.kind
            if request.kind == "buffers" then
                fixture.equal(1, #request.buffers)
                fixture.equal(modified, request.buffers[1].buf)
                return "discard"
            end
            fixture.equal(1, #request.buffers)
            fixture.equal(ordinary, request.buffers[1].buf)
            return "stop"
        end,
    })
    assert(ok, err)
    fixture.equal({ "buffers", "jobs" }, requests)
    assert(not vim.api.nvim_buf_is_valid(modified))
    assert(not vim.api.nvim_buf_is_valid(ordinary))
    assert(vim.fn.jobwait({ job }, 1000)[1] ~= -1)
    fixture.equal(0, vim.fn.filereadable(owner.metadata.cwd .. "/recursive-launch"))
    assert(not vim.api.nvim_buf_is_valid(second.bufnr))
    local recovered = t.attach(item.id)
    fixture.equal(pid, t.pid(recovered))
    t.probe(recovered, "safe-unload", "after-consent")
end)
