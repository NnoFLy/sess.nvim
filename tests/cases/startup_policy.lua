-- Until resume integration lands, substitute only the agreed resume API boundary.
-- Observe the resulting editor contents, not helper names or invocation counts.
local boundary = [[
package.preload["sess.api.resume"] = function()
    return {
        startup = function(mode)
            vim.api.nvim_buf_set_lines(0, 0, -1, false, { "resumed " .. mode })
            return true, nil, {}
        end,
        exit = function() return true, nil, {} end,
    }
end
]]

local function setup(mode)
    return boundary
        .. string.format(
            [[
assert(require("sess").setup({
    store_path = vim.fn.getcwd() .. "/store",
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

fixture.startup(setup("current") .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "resumed current")
]]))

fixture.startup(setup("all") .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "resumed all")
]]))

fixture.startup(setup("none") .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
]]))

for _, args in ipairs({
    { "-c", "let g:explicit = 1" },
    { "+let g:explicit = 1" },
    { "--cmd", "let g:explicit = 1" },
}) do
    fixture.startup(setup("current") .. observe([[
        assert(vim.g.explicit == 1)
        assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
    ]]), args)
end

-- Meaningful hidden buffers must not be discarded just because the window is empty.
fixture.startup(setup("all") .. [[
local hidden = vim.api.nvim_create_buf(false, true)
]] .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
    assert(vim.api.nvim_buf_is_valid(hidden) and vim.bo[hidden].buftype == "nofile")
]]))

fixture.startup(setup("current") .. [[
vim.cmd.lcd(vim.fn.getcwd())
]] .. observe([[
    assert(vim.fn.haslocaldir() == 1)
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
]]))

-- Ordinary option operands are not files or commands, even when prefixed '+'.
for _, args in ipairs({
    { "--startuptime", "+startup.log" },
    { "-W", "+keys" },
    { "-i", "+shada" },
    { "--" },
    { "-o1", "-p1" },
}) do
    fixture.startup(setup("current") .. observe([[
        assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "resumed current")
    ]]), args)
end

local original = fixture.root .. "/original.txt"
vim.fn.writefile({ "explicit file" }, original)
fixture.startup(setup("current") .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "explicit file")
    assert(vim.api.nvim_buf_get_name(0):match("original.txt$"))
]]), { original })

vim.fn.writefile({ "separator file" }, fixture.root .. "/+literal")
fixture.startup(setup("all") .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "separator file")
]]), { "--", "+literal" })

fixture.startup(setup("current") .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "stdin content")
]]), { "-" }, "stdin content\n")

local script = fixture.root .. "/explicit.vim"
vim.fn.writefile({ "let g:explicit = 1" }, script)
fixture.startup(setup("all") .. observe([[
    assert(vim.g.explicit == 1)
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
]]), { "-S", script })

-- Every skip must retain the context, not just refrain from resuming.
for _, case in ipairs({
    {
        'vim.v.this_session = "explicit-session.vim"',
        'assert(vim.v.this_session == "explicit-session.vim")',
    },
    {
        'vim.api.nvim_buf_set_lines(0, 0, -1, false, { "work" })',
        'assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "work")',
    },
    { "vim.bo.modified = true", "assert(vim.bo.modified)" },
    { 'vim.bo.buftype = "nofile"', 'assert(vim.bo.buftype == "nofile")' },
    { 'vim.cmd("split")', "assert(#vim.api.nvim_list_wins() == 2)" },
    { 'vim.cmd("tabnew")', "assert(#vim.api.nvim_list_tabpages() == 2)" },
    { "vim.cmd.tcd(vim.fn.getcwd())", "assert(vim.fn.haslocaldir(-1, 0) ~= 0)" },
    { "local b = vim.api.nvim_create_buf(true, false)", "assert(#vim.api.nvim_list_bufs() == 2)" },
    {
        'local b = vim.api.nvim_create_buf(false, false); vim.api.nvim_buf_set_name(b, "hidden.txt")',
        "assert(#vim.api.nvim_list_bufs() == 2)",
    },
    {
        'local b = vim.api.nvim_create_buf(false, false); vim.api.nvim_buf_set_lines(b, 0, -1, false, { "hidden work" })',
        "assert(#vim.api.nvim_list_bufs() == 2)",
    },
    {
        'local b = vim.api.nvim_create_buf(false, false); vim.api.nvim_open_win(b, false, { relative = "editor", row = 0, col = 0, width = 8, height = 2 })',
        "assert(#vim.api.nvim_list_wins() == 2)",
    },
}) do
    fixture.startup(
        'vim.api.nvim_create_autocmd("VimEnter", { callback = function()\n'
            .. case[1]
            .. "\nend })\n"
            .. setup("all")
            .. observe(case[2] .. [[
        assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] ~= "resumed all")
    ]])
    )
end

-- A running terminal remains live when startup is skipped.
fixture.startup(setup("all") .. [[
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function()
        vim.fn.jobstart({ "sh", "-c", "sleep 60" }, { term = true })
    end,
})
]] .. observe([[
    assert(vim.bo.buftype == "terminal")
    assert(vim.fn.jobwait({ vim.b.terminal_job_id }, 0)[1] == -1)
]]))

-- Transient initialization is not an activity-history veto.
fixture.startup(setup("current") .. [[
vim.cmd("split")
vim.cmd("close")
]] .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "resumed current")
]]))

-- A harmless extra unlisted empty normal buffer is not meaningful work.
fixture.startup(setup("current") .. [[
vim.api.nvim_create_buf(false, false)
]] .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "resumed current")
]]))

-- Register work before setup, but execute it only after the VimEnter inspection.
for _, mutation in ipairs({
    'vim.api.nvim_buf_set_lines(0, 0, -1, false, { "late work" })',
    'vim.api.nvim_buf_set_lines(0, 0, -1, false, { "temporary" }); vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" }); vim.bo.modified = false',
    "vim.api.nvim_set_current_buf(vim.api.nvim_create_buf(true, false))",
    'vim.cmd("split")',
    "vim.cmd.cd(vim.env.SESS_TEST_REPO)",
    "vim.cmd.lcd(vim.fn.getcwd())",
}) do
    fixture.startup([[
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function() vim.schedule(function()
]] .. mutation .. [[
    end) end,
})
]] .. setup("all") .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] ~= "resumed all")
]]))
end

fixture.startup(setup("all") .. [[
assert(require("sess.api").session.create(vim.fn.getcwd()))
local original_id = require("sess.api").state.current().id
]] .. observe([[
    assert(require("sess.api").state.current().id == original_id)
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
]]))

-- Active membership also disqualifies startup when no session is current.
fixture.startup(setup("all") .. [[
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
fixture.startup(boundary .. [[
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
]] .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
]]))

fixture.startup(setup("current") .. [[
local ok, err = require("sess").setup({ smart_auto_load = "all" })
assert(not ok and err:find("already loaded", 1, true))
]] .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "resumed current")
]]))

-- Even an empty stdin read has explicit provenance. The actual '-' input path
-- above uses real stdin; this event covers Neovim's implicit-read notification.
fixture.startup(setup("all") .. [[
vim.api.nvim_exec_autocmds("StdinReadPre", {})
]] .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
]]))

-- Startup failure diagnostics include warnings from earlier committed work.
local failure = fixture.startup(setup("all") .. [[
package.preload["sess.api.resume"] = function()
    return {
        startup = function()
            return false, "startup failed", {}, { "partial startup warning" }
        end,
        exit = function() return true end,
    }
end
]] .. observe([[
    assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
]]))
assert(failure.stderr:find("startup failed", 1, true))
assert(failure.stderr:find("partial startup warning", 1, true))

-- Normal exit is always delegated, including none mode with autosave disabled.
for _, mode in ipairs({ "none", "current", "all" }) do
    local result = fixture.startup(setup(mode) .. [[
-- Capture the notification boundary synchronously: newer Neovim may defer its
-- own UI rendering until after VimLeavePre, when the process is already gone.
vim.notify = function(message) io.stderr:write(message .. "\n") end
package.preload["sess.api.resume"] = function()
    return {
        startup = function() return true end,
        exit = function(options)
            assert(options.auto_save == false)
            return false, "exit failed " .. options.smart_auto_load, {}, { "exit warning" }
        end,
    }
end
]] .. observe(""))
    assert(result.stderr:find("exit failed " .. mode, 1, true))
    assert(result.stderr:find("exit warning", 1, true))
end
