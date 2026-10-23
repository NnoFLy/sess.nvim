-- Eligibility is exercised with a real saved session at genuine startup.
local function setup(mode)
    return string.format(
        [[
assert(require("sess").setup({
    store_path = vim.env.SESS_TEST_ROOT .. "/store",
    smart_auto_load = %q,
    auto_save = false,
    tabline = { enabled = false },
}))
]],
        mode
    )
end

local function observe(assertions)
    return [[
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        vim.defer_fn(function()
            check(function()
]] .. assertions .. [[
            end)
        end, 20)
    end,
})
]]
end

local function untouched(assertions)
    return observe((assertions or "") .. [[
        assert(require("sess.api").state.current() == nil)
        assert(#require("sess.api").state.active() == 0)
    ]])
end

local function restored(assertions)
    -- Observe committed loading instead of racing a timer against snapshot work.
    return [[
vim.api.nvim_create_autocmd("User", {
    pattern = "SessLoaded", once = true,
    callback = function() vim.schedule(function() check(function()
        local api = require("sess.api")
        assert(api.state.current().id == "startup")
        assert(#api.state.active() == 1 and api.state.active()[1].id == "startup")
        assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "restored context")
]] .. (assertions or "") .. [[
    end) end) end,
})
]]
end

fixture.startup(setup("none") .. observe([[
    local root = vim.env.SESS_TEST_ROOT
    local api = require("sess.api")
    assert(api.session.create(root, { id = "startup" }))
    vim.fn.writefile({ "restored context" }, root .. "/saved.txt")
    vim.cmd.edit(root .. "/saved.txt")
    assert(api.session.save())
]]))

local function startup(code, args, stdin)
    -- Each process starts from the same published selection; tests that manage
    -- other sessions must not change the next process's resume input.
    vim.fn.writefile(
        { '{"version":1,"active_ids":["startup"],"current_id":"startup"}' },
        fixture.root .. "/store/resume.json"
    )
    return fixture.startup(code, args, stdin)
end

startup(setup("current") .. restored())

startup(setup("all") .. restored())

startup(setup("none") .. untouched([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
]]))

for _, args in ipairs({
    { "-c", "let g:explicit = 1" },
    { "+let g:explicit = 1" },
    { "--cmd", "let g:explicit = 1" },
}) do
    startup(setup("current") .. untouched([[
        assert(vim.g.explicit == 1)
        assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
    ]]), args)
end

-- Hidden plugin buffers do not veto restoration and remain manually recoverable.
startup(setup("all") .. [[
local hidden = vim.api.nvim_create_buf(false, true)
]] .. restored([[
    assert(vim.api.nvim_buf_is_valid(hidden) and vim.bo[hidden].buftype == "nofile")
    assert(not vim.bo[hidden].buflisted)
]]))

startup(setup("current") .. [[
vim.cmd.lcd(vim.fn.getcwd())
]] .. restored())

-- Ordinary option operands are not files or commands, even when prefixed '+'.
for _, args in ipairs({
    { "--startuptime", "+startup.log" },
    { "-W", "+keys" },
    { "-i", "+shada" },
    { "--" },
    { "-o1", "-p1" },
}) do
    startup(setup("current") .. restored(), args)
end

local original = fixture.root .. "/original.txt"
vim.fn.writefile({ "explicit file" }, original)
startup(setup("current") .. untouched([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "explicit file")
    assert(vim.api.nvim_buf_get_name(0):match("original.txt$"))
]]), { original })

startup(setup("all") .. untouched(), { fixture.root })

vim.fn.writefile({ "separator file" }, fixture.root .. "/+literal")
startup(setup("all") .. untouched([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "separator file")
]]), { "--", "+literal" })

startup(setup("current") .. untouched([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "stdin content")
]]), { "-" }, "stdin content\n")

local script = fixture.root .. "/explicit.vim"
vim.fn.writefile({ "let g:explicit = 1" }, script)
startup(setup("all") .. untouched([[
    assert(vim.g.explicit == 1)
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
]]), { "-S", script })

-- Native session provenance still suppresses automatic loading.
startup(setup("all") .. [[
vim.v.this_session = "explicit-session.vim"
]] .. untouched([[
    assert(vim.v.this_session == "explicit-session.vim")
]]))

-- Plugin-created layouts, views, cwd scopes and buffers do not imply user intent.
for _, preparation in ipairs({
    'vim.api.nvim_buf_set_lines(0, 0, -1, false, { "work" })',
    "vim.bo.modified = true",
    'vim.bo.buftype = "nofile"',
    'vim.cmd("split")',
    'vim.cmd("tabnew")',
    "vim.cmd.tcd(vim.fn.getcwd())",
    "vim.api.nvim_create_buf(true, false)",
    'local b = vim.api.nvim_create_buf(false, false); vim.api.nvim_buf_set_name(b, "hidden.txt")',
    'local b = vim.api.nvim_create_buf(false, false); vim.api.nvim_buf_set_lines(b, 0, -1, false, { "hidden work" })',
    'local b = vim.api.nvim_create_buf(false, true); vim.api.nvim_open_win(b, true, { relative = "editor", row = 0, col = 0, width = 8, height = 2 })',
}) do
    startup(
        'vim.api.nvim_create_autocmd("VimEnter", { callback = function()\n'
            .. preparation
            .. "\nend })\n"
            .. setup("all")
            .. restored()
    )
end

-- Transient initialization is not an activity-history veto.
startup(setup("current") .. [[
vim.cmd("split")
vim.cmd("close")
]] .. restored())

-- A harmless extra unlisted empty normal buffer is not meaningful work.
startup(setup("current") .. [[
vim.api.nvim_create_buf(false, false)
]] .. restored())

-- Programmatic activity between inspection and dispatch is not typed input.
for _, mutation in ipairs({
    'vim.api.nvim_buf_set_lines(0, 0, -1, false, { "late work" })',
    'vim.api.nvim_buf_set_lines(0, 0, -1, false, { "temporary" }); vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" }); vim.bo.modified = false',
    "vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))",
    'vim.cmd("split")',
    "vim.cmd.cd(vim.env.SESS_TEST_REPO)",
    "vim.cmd.lcd(vim.fn.getcwd())",
}) do
    startup([[
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function() vim.schedule(function()
]] .. mutation .. [[
    end) end,
})
 ]] .. setup("all") .. restored())
end

-- Exercise real input processing, not a mocked changedtick or on_key callback.
-- Non-typed feedkeys are programmatic; the 't' flag uses Neovim's typed path.
for _, typed in ipairs({ false, true }) do
    local input = [[
local listeners_before = vim.on_key()
vim.api.nvim_create_autocmd("VimEnter", { callback = function()
    vim.schedule(function()
        local keys = vim.api.nvim_replace_termcodes("ityped work<Esc>", true, false, true)
        vim.api.nvim_feedkeys(keys, ]] .. (typed and '"ntx"' or '"nx"') .. [[, false)
    end)
end })
]]
    local assertions = [[assert(vim.on_key() == listeners_before)]]
    if typed then
        startup(input .. setup("all") .. untouched(assertions .. [[
assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "typed work")
]]))
    else
        startup(input .. setup("all") .. restored(assertions))
    end
end

-- Internal managed reconfiguration invalidates old registrations and input
-- listeners. A deferred operation is one-shot, even with a synthetic VimEnter.
startup([[
local listeners_before = vim.on_key()
]] .. setup("all") .. [[
local group = vim.api.nvim_create_augroup("SessNvimInternal", { clear = true })
require("sess.startup").setup(group, "current", function() error("stale registration") end)
vim.api.nvim_clear_autocmds({ group = group, event = "VimEnter" })
local calls = 0
require("sess.startup").setup(group, "all", function(mode)
    calls = calls + 1
    assert(mode == "all")
end)
]] .. untouched([[
assert(calls == 1)
assert(vim.on_key() == listeners_before)
vim.api.nvim_exec_autocmds("VimEnter", {})
assert(calls == 1)
]]))

-- Reconfiguration during the deferred gap cancels the older scheduled token;
-- late registration never performs catch-up loading.
startup([[
local listeners_before = vim.on_key()
vim.api.nvim_create_autocmd("VimEnter", { callback = function()
    vim.schedule(function()
        local group = vim.api.nvim_create_augroup("SessNvimInternal", { clear = true })
        require("sess.startup").setup(group, "none", function() error("disabled") end)
    end)
end })
]] .. setup("all") .. untouched([[
assert(vim.on_key() == listeners_before)
]]))

startup(setup("all") .. [[
assert(require("sess.api").session.load("startup"))
local original_id = require("sess.api").state.current().id
]] .. observe([[
    assert(require("sess.api").state.current().id == original_id)
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "restored context")
]]))

-- A session started in the deferred gap still wins, even if then unloaded.
startup([[
vim.api.nvim_create_autocmd("VimEnter", { callback = function()
    vim.schedule(function()
        local api = require("sess.api")
        assert(api.session.load("startup"))
        assert(api.session.unload())
    end)
end })
]] .. setup("all") .. [[
vim.api.nvim_create_autocmd("User", { pattern = "SessUnloaded", once = true,
    callback = function() vim.schedule(function() check(function()
        assert(require("sess.state").has_managed_sessions())
        assert(require("sess.api").state.current() == nil)
        assert(#require("sess.api").state.active() == 0)
    end) end) end,
})
]])

startup([[
vim.api.nvim_create_autocmd("VimEnter", { callback = function()
    vim.schedule(function() vim.v.this_session = "late-native.vim" end)
end })
]] .. setup("all") .. untouched([[
assert(vim.v.this_session == "late-native.vim")
]]))

-- Active membership also disqualifies startup when no session is current.
startup(setup("all") .. [[
local api = require("sess.api")
local a = vim.fn.getcwd() .. "/active-a"
local b = vim.fn.getcwd() .. "/active-b"
vim.fn.mkdir(a, "p")
vim.fn.mkdir(b, "p")
assert(api.session.create(a))
local active_id = api.state.current().id
assert(api.session.create(b))
assert(api.session.unload())
assert(api.state.current() == nil)
]] .. observe([[
    assert(require("sess.api").state.active()[1].id == active_id)
    assert(require("sess.api").state.current() == nil)
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
]]))

-- Late public setup does not install a catch-up mutation.
startup([[
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        vim.schedule(function()
            assert(require("sess").setup({
                store_path = vim.fn.getcwd() .. "/store",
                smart_auto_load = "all",
                auto_save = false,
            }))
        end)
    end,
})
]] .. untouched([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
]]))

startup(setup("current") .. [[
local ok, err = require("sess").setup({ smart_auto_load = "all" })
assert(not ok and err:find("already loaded", 1, true))
]] .. restored())

-- Even an empty stdin read has explicit provenance. The actual '-' input path
-- above uses real stdin; this event covers Neovim's implicit-read notification.
startup(setup("all") .. [[
vim.api.nvim_exec_autocmds("StdinReadPre", {})
]] .. untouched([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
]]))

-- Partial startup errors plus earlier diagnostics are exercised by the real
-- before-hook and snapshot-execution failures in resume_transitions.lua.
-- Exit error/warning visibility and preserved history on failed publication are
-- exercised with filesystem failures in resume_exit.lua.

-- Normal exit publishes managed membership in every mode, even without autosave.
for _, mode in ipairs({ "none", "current", "all" }) do
    local completion = mode == "none" and observe or restored
    startup(setup(mode) .. completion(string.format(
        [[
        local api = require("sess.api")
        if api.state.current() then assert(api.session.unload()) end
        local path = vim.env.SESS_TEST_ROOT .. "/exit-" .. %q
        vim.fn.mkdir(path, "p")
        assert(api.session.create(path, { id = "exit-" .. %q }))
    ]],
        mode,
        mode
    )))
    local record =
        vim.json.decode(table.concat(vim.fn.readfile(fixture.root .. "/store/resume.json"), "\n"))
    fixture.equal({ "exit-" .. mode }, record.active_ids)
    fixture.equal("exit-" .. mode, record.current_id)
end
