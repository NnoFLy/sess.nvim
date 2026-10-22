local terminal = dofile(vim.env.SESS_TEST_REPO .. "/tests/helpers/terminal.lua")
terminal.run(function(t)
    local api = require("sess.api")
    local result_file = fixture.root .. "/normal-exit.json"
    local config = fixture.root .. "/normal-exit.lua"
    local code = string.format(
        [[
vim.opt.runtimepath:prepend(vim.env.SESS_TEST_REPO)
vim.opt.shadafile = 'NONE'
vim.opt.swapfile = false
vim.opt.sessionoptions = {'buffers', 'curdir', 'tabpages', 'winsize', 'terminal'}
vim.schedule(function()
    local ok, err = xpcall(function()
        assert(require('sess').setup({store_path=%q, smart_auto_load='none', auto_save=false}))
        vim.o.shell = '/bin/sh'
        local api = require('sess.api')
        local created, failure, owner = api.session.create(%q)
        assert(created, failure)
        local launched, launch_err, item = api.terminal.launch(%q)
        assert(launched, launch_err)
        assert(vim.wait(5000, function() return vim.fn.filereadable(%q) == 1 end, 20))
        assert(api.session.rename(owner.id, 'renamed-owner'))
        assert(api.session.save())
        vim.fn.writefile({vim.json.encode({owner=owner.id, id=item.id, execution=item.execution})}, %q)
        -- Deliberately normal :qa, not fixture.startup's forced :qa!.
        vim.cmd('qa')
    end, debug.traceback)
    if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit 1') end
end)
]],
        fixture.root .. "/store",
        fixture.directory("owner"),
        t.probe_command("continuity"),
        fixture.root .. "/continuity.pid",
        result_file
    )
    vim.fn.writefile(vim.split(code, "\n", { plain = true }), config)
    local child = vim.system(
        { vim.v.progpath, "--headless", "-u", config, "-i", "NONE", "--noplugin", "-n" },
        {
            cwd = fixture.root,
            env = { TMUX = "", TMUX_PANE = "" },
            text = true,
        }
    )
    local result = child:wait(15000)
    if result.code == 124 then
        child:kill(9)
    end
    assert(result.code == 0, "normal qa failed: " .. (result.stderr or "") .. (result.stdout or ""))
    local saved = vim.json.decode(t.read(result_file))
    local original = t.read(fixture.root .. "/continuity.pid")
    local ok, err, owner = api.session.get_by_id(saved.owner)
    assert(ok and owner, err)
    fixture.equal("renamed-owner", owner.metadata.name)
    assert(api.session.load(owner.id))
    -- Snapshot references stay inert even with sessionoptions+=terminal.
    fixture.equal({ "launch" }, vim.fn.readfile(fixture.root .. "/continuity.count"))
    for _, channel in ipairs(vim.api.nvim_list_chans()) do
        assert(channel.mode ~= "terminal", "loading layout must not automatically attach or launch")
    end
    local item = t.attach(saved.id)
    fixture.equal(saved.execution, item.execution)
    fixture.equal(owner.id, item.execution.owner_id)
    fixture.equal(original .. "\n", t.pid(item))
    t.probe(item, "continuity", "after-normal-qa")
    local _, _, other = api.session.create(fixture.directory("other"))
    assert(other and api.state.current().id == other.id)
    local switched = t.attach(saved.id)
    t.probe(switched, "continuity", "after-switch")
    assert(api.session.load(owner.id))
    local loaded = t.attach(saved.id)
    t.probe(loaded, "continuity", "after-load")
    assert(api.session.unload(owner.id, {
        confirm = function()
            error("managed attachment must not ask to stop execution")
        end,
    }))
    local detached = t.attach(saved.id)
    t.probe(detached, "continuity", "after-unload")
    fixture.equal(original .. "\n", t.pid(detached))
    fixture.equal(owner.id, detached.execution.owner_id)
    fixture.equal(nil, api.state.current())
end)
