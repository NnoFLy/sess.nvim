-- Exercise real UI2 with an attached embedded UI: headless enable() is a no-op.
if not pcall(require, "vim._core.ui2") then
    return
end

fixture.setup()
local api = require("sess.api")
local file = fixture.root .. "/saved.txt"
vim.fn.writefile({ "resumed with UI2" }, file)
assert(api.session.create(fixture.root, { id = "ui2-session" }))
vim.cmd.edit(file)
assert(api.session.save())
assert(api.resume.exit())

local function startup(mode, preparation, expected_id, expected_text)
    local config = fixture.root .. "/ui2-init.lua"
    local result_path = fixture.root .. "/ui2-result.json"
    vim.fn.delete(result_path)
    local code = [[
vim.opt.runtimepath:prepend(vim.env.SESS_TEST_REPO)
vim.opt.shadafile = "NONE"
vim.opt.swapfile = false
vim.opt.cmdheight = 0
require("vim._core.ui2").enable({ enable = true })
]] .. (preparation or "") .. string.format(
        [[
assert(require("sess").setup({
    store_path = vim.env.SESS_TEST_ROOT .. "/store",
    smart_auto_load = %q,
    auto_save = false,
    tabline = { enabled = false },
}))
]],
        mode
    ) .. [[
local function finish()
    local ok, result = xpcall(function()
        local current = require("sess.api").state.current()
        local ui2 = require("vim._core.ui2")
        for name, win in pairs(ui2.wins) do
            assert(vim.api.nvim_win_is_valid(win), name .. " UI2 window was closed")
            assert(vim.api.nvim_buf_is_valid(ui2.bufs[name]), name .. " UI2 buffer was deleted")
            assert(vim.api.nvim_win_get_buf(win) == ui2.bufs[name])
        end
        if _G.extra_window then assert(not vim.api.nvim_win_is_valid(_G.extra_window)) end
        if _G.extra_buffer then assert(vim.api.nvim_buf_is_valid(_G.extra_buffer)) end
        return { id = current and current.id or false,
            text = vim.api.nvim_buf_get_lines(0, 0, -1, false) }
    end, debug.traceback)
    vim.fn.writefile({ vim.json.encode({ ok = ok, result = result }) },
        vim.env.SESS_TEST_ROOT .. "/ui2-result.json")
    vim.cmd("qa!")
end
]]
    if expected_id then
        code = code
            .. [[
vim.api.nvim_create_autocmd("User", { pattern = "SessLoaded", once = true,
    callback = function() vim.schedule(finish) end,
})
]]
    else
        code = code
            .. [[
vim.api.nvim_create_autocmd("VimEnter", {
    callback = function() vim.defer_fn(finish, 100) end,
})
]]
    end
    vim.fn.writefile(vim.split(code, "\n", { plain = true }), config)

    local channel = vim.fn.jobstart({
        vim.v.progpath,
        "--embed",
        "-u",
        config,
        "-i",
        "NONE",
        "--noplugin",
        "-n",
    }, { cwd = fixture.root })
    assert(channel > 0)
    -- Raw transport discards redraw notifications instead of asking the parent
    -- Neovim to interpret a second editor's UI protocol as its own.
    vim.fn.chansend(
        channel,
        vim.mpack.encode({
            0,
            1,
            "nvim_ui_attach",
            { 80, 24, { rgb = true, ext_linegrid = true } },
        })
    )
    local finished = vim.wait(5000, function()
        return vim.fn.jobwait({ channel }, 0)[1] ~= -1
    end, 20)
    if not finished then
        vim.fn.jobstop(channel)
    end
    assert(finished, "embedded UI2 startup timed out")
    local result = vim.json.decode(table.concat(vim.fn.readfile(result_path), "\n"))
    assert(result.ok, result.result)
    fixture.equal(expected_id, result.result.id)
    fixture.equal({ expected_text }, result.result.text)
end

startup("all", nil, "ui2-session", "resumed with UI2")
startup("current", nil, "ui2-session", "resumed with UI2")

-- Presentation updates between the two eligibility checks are harmless.
startup(
    "all",
    [[
vim.api.nvim_create_autocmd("VimEnter", { callback = function()
    vim.schedule(function() vim.notify("UI2 startup message") end)
end })
]],
    "ui2-session",
    "resumed with UI2"
)

-- Unrelated plugin floats and special buffers also permit restoration.
startup(
    "all",
    [[
_G.extra_buffer = vim.api.nvim_create_buf(false, true)
_G.extra_window = vim.api.nvim_open_win(_G.extra_buffer, false, {
    relative = "editor", row = 0, col = 0, width = 8, height = 2,
})
]],
    "ui2-session",
    "resumed with UI2"
)
startup(
    "all",
    [[
_G.extra_buffer = vim.api.nvim_create_buf(false, true)
]],
    "ui2-session",
    "resumed with UI2"
)

-- Programmatic edits before deferred restore do not claim typed provenance.
startup(
    "all",
    [[
vim.api.nvim_create_autocmd("VimEnter", { callback = function()
    vim.schedule(function() vim.api.nvim_buf_set_lines(0, 0, -1, false, { "late work" }) end)
end })
]],
    "ui2-session",
    "resumed with UI2"
)

-- Generated :only may close UI2 floats before a later snapshot error. Rollback
-- must leave both the initial editor context and editor-owned UI operational.
vim.fn.writefile(
    { "throw 'UI2 snapshot failure'" },
    fixture.root .. "/store/sessions/ui2-session/session.vim",
    "a"
)
startup("all", nil, false, "")
