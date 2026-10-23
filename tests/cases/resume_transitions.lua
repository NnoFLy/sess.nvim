local root = fixture.root
local path = root .. "/store/resume.json"
local function after(code)
    return [[
vim.api.nvim_create_autocmd("VimEnter", { callback = function() vim.defer_fn(function() check(function()
]] .. code .. [[
end) end, 200) end })
]]
end
local setup = [[
local root = vim.env.SESS_TEST_ROOT
local api = require("sess.api")
]]
fixture.startup(setup .. [[
assert(require("sess").setup({ store_path = root .. "/store", smart_auto_load = "none", auto_save = false }))
]] .. after([[
for _, id in ipairs({ "a", "b", "c", "d" }) do
    local dir = root .. "/" .. id
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "context " .. id }, dir .. "/file.txt")
    assert(api.session.create(dir, { id = id }))
    vim.cmd.edit(dir .. "/file.txt")
    assert(api.session.save())
end
]]))
local function publish()
    vim.fn.writefile({ '{"version":1,"active_ids":["a","b","c","d"],"current_id":"d"}' }, path)
end
local function restore(hooks, assertions, events)
    publish()
    return fixture.startup(setup .. string.format(
        [[
local seen = {}
assert(require("sess").setup({ store_path = root .. "/store", smart_auto_load = "all", auto_save = false,
    tabline = { enabled = false }, hooks = %s }))
]],
        hooks
    ) .. (events or "") .. after(assertions))
end
local partial = [[
assert(api.state.current().id == "a")
assert(vim.deep_equal({ "a" }, vim.tbl_map(function(s) return s.id end, api.state.active())))
assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "context a")
]]
local before = restore(
    [[{
    before_transition = function(event)
        if event.session.id == "b" then error("before veto") end
    end,
    after_operation = function(event)
        assert(api.state.current().id == event.current.id)
        local ok, err = api.session.unload()
        assert(not ok and err:find("already in progress", 1, true))
        if event.operation == "load" then error("committed load warning") end
    end,
}]],
    partial
)
assert(before.stderr:find("before veto", 1, true))
assert(before.stderr:find("committed load warning", 1, true))

-- A snapshot can pass preflight but fail execution. Earlier commits stay active;
-- failing transition rolls back its reversible layout, stops before C/D, and
-- retains diagnostics from the ordinary outgoing save preceding execution.
local snapshot = root .. "/store/sessions/b/session.vim"
local old = vim.fn.readfile(snapshot)
vim.fn.writefile(
    { "let SessionLoad = 1", "throw 'execution failure'", "unlet SessionLoad" },
    snapshot
)
local execution = restore(
    [[{
    after_operation = function(event)
        if event.operation == "save" then error("outgoing save warning") end
    end,
}]],
    partial
)
assert(execution.stderr:find("execution failure", 1, true), execution.stderr)
assert(execution.stderr:find("outgoing save warning", 1, true), execution.stderr)
vim.fn.writefile(old, snapshot)

-- After hooks/subscribers run after commits, cannot recurse, and do not halt
-- restoration. Ordinary outgoing transition saves continue to be observed.
local complete = restore(
    [[{
    before_transition = function(event)
        assert(event.operation == "load")
        seen[#seen + 1] = event.session.id
    end,
    after_operation = function(event)
        assert(api.state.current().id == event.current.id)
        local ok, err = api.session.load("a")
        assert(not ok and err:find("already in progress", 1, true))
        error("after warning " .. event.operation)
    end,
}]],
    [[
assert(api.state.current().id == "d")
assert(#api.state.active() == 4)
assert(vim.deep_equal({ "a", "b", "c", "d" }, seen))
assert(vim.g.saves == 3)
]],
    [[
vim.g.saves = 0
vim.api.nvim_create_autocmd("User", { pattern = "SessSaved", callback = function(event)
    assert(api.state.current().id == event.data.current.id)
    vim.g.saves = vim.g.saves + 1
end })
vim.api.nvim_create_autocmd("User", { pattern = "SessLoaded", callback = function(event)
    assert(api.state.current().id == event.data.session.id)
    error("subscriber warning")
end })
]]
)
assert(complete.stderr:find("after warning", 1, true))
assert(complete.stderr:find("subscriber warning", 1, true))
