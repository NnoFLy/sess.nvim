vim.o.showtabline = 2
local warnings = {}
vim.notify = function(message)
    warnings[#warnings + 1] = message
end
vim.g.sess_sandbox_attack = false
vim.cmd([[
    function! SessSandboxGuard() abort
        if g:sess_sandbox_attack
            return luaeval('SessSandboxAttack()')
        endif
        return 'sandbox-safe native format'
    endfunction
]])
local original = "%!SessSandboxGuard()"
vim.g.sess_sandbox_original = original
vim.cmd("sandbox let &tabline = g:sess_sandbox_original")
assert(require("sess").setup({
    store_path = fixture.root .. "/store",
    smart_auto_load = "none",
    auto_save = false,
    tabline = { enabled = true },
}))
local tabline = require("sess.ui.tabline")
local sidebar = require("sess.ui.sidebar")
assert(sidebar.open())
-- Only native redraw respects the hidden insecure-option flag; the statusline
-- evaluation API deliberately does not, so it cannot validate this boundary.
vim.cmd.redrawtabline()
assert(vim.wait(200, function()
    return vim.o.tabline == original
end))
assert(not tabline.heading_visible())
fixture.equal(1, #warnings)
assert(warnings[1]:find("sandboxed tabline left unchanged", 1, true))
vim.cmd.redrawtabline()
vim.wait(20)
fixture.equal(1, #warnings)
local called = false
_G.SessSandboxAttack = function()
    called = true
    return "UNSAFE"
end
-- Restoration itself must retain the insecure flag, not merely the wrapper.
vim.g.sess_sandbox_attack = true
pcall(vim.cmd.redrawtabline)
assert(not called, "restoring original option lost its sandbox provenance")
for _, unsafe in ipairs({ "%!v:lua.SessSandboxAttack()", "%{v:lua.SessSandboxAttack()}" }) do
    vim.g.sess_sandbox_original = unsafe
    vim.cmd("sandbox let &tabline = g:sess_sandbox_original")
    assert(tabline.install()) -- A failing native provider must not abort setup.
    pcall(vim.cmd.redrawtabline)
    vim.wait(20)
    assert(not called, "captured option expression escaped native sandbox")
    assert(not tabline.heading_visible())
end
assert(sidebar.close())
