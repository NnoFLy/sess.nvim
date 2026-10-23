vim.o.showtabline = 0
local warnings = {}
vim.notify = function(message)
    warnings[#warnings + 1] = message
end
vim.g.sess_deferred_attack = false
vim.cmd([[
    function! SessDeferredSandboxGuard() abort
        if g:sess_deferred_attack
            return luaeval('SessDeferredSandboxAttack()')
        endif
        return 'deferred sandbox-safe native format'
    endfunction
]])
local original = "%!SessDeferredSandboxGuard()"
vim.g.sess_deferred_original = original
vim.cmd("sandbox let &tabline = g:sess_deferred_original")
assert(require("sess").setup({
    store_path = fixture.root .. "/store",
    smart_auto_load = "none",
    auto_save = false,
    tabline = { enabled = true },
}))
local sidebar = require("sess.ui.sidebar")
local tabline = require("sess.ui.tabline")
assert(sidebar.open())
vim.wait(50) -- Finish setup/sidebar work before the first visible native render.
local wrapper = vim.o.tabline
assert(wrapper ~= original)
fixture.equal(0, #warnings)
vim.o.showtabline = 2
vim.api.nvim_exec_autocmds("OptionSet", { pattern = "showtabline" })
vim.wait(50) -- Also finish option reconciliation before the first native redraw.
fixture.equal(wrapper, vim.o.tabline)
fixture.equal(0, #warnings)

local function idle_without_scheduling()
    local schedule = vim.schedule
    local scheduled = 0
    vim.schedule = function(callback)
        scheduled = scheduled + 1
        schedule(callback)
    end
    vim.api.nvim_exec_autocmds("SafeState", {})
    vim.schedule = schedule
    fixture.equal(0, scheduled)
end
idle_without_scheduling() -- A bridge that has not rendered does no idle work.
-- Native redraw respects option trust; nvim_eval_statusline() does not.
vim.cmd.redrawtabline()
-- The runner is still inside startup's -c command, which suppresses real idle
-- transitions. Exercise the SafeState event that follows rendering interactively.
vim.api.nvim_exec_autocmds("SafeState", {})
vim.wait(50)
fixture.equal(original, vim.o.tabline)
fixture.equal(2, vim.o.showtabline)
fixture.equal(1, #warnings)
assert(warnings[1]:find("sandboxed tabline left unchanged", 1, true))
assert(not tabline.heading_visible())
local buf = vim.api.nvim_win_get_buf(sidebar.tabline_geometry().win)
fixture.equal("ACTIVE SESSIONS", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
vim.cmd.redrawtabline()
for _ = 1, 3 do
    idle_without_scheduling()
    vim.wait(20)
end
fixture.equal(original, vim.o.tabline)
fixture.equal(1, #warnings)
local called = false
_G.SessDeferredSandboxAttack = function()
    called = true
    return "UNSAFE"
end
vim.g.sess_deferred_attack = true
pcall(vim.cmd.redrawtabline)
assert(not called, "deferred restoration lost the original option's sandbox flag")
assert(sidebar.close())
