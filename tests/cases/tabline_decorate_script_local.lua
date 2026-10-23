vim.o.showtabline = 2
local path = fixture.root .. "/native-provider.vim"
vim.fn.writefile({
    "let s:label = 'script-local'",
    "function! s:Provider() abort",
    "    return '%1T%#ErrorMsg#' . s:label . '%T'",
    "endfunction",
    "function! s:Evaluate(format) abort",
    "    return nvim_eval_statusline(a:format, {'use_tabline': v:true, 'maxwidth': &columns}).str",
    "endfunction",
    "function! s:Install() abort",
    "    return luaeval(\"require('sess.ui.tabline').install()\")",
    "endfunction",
    "let g:sess_native_sid = expand('<SID>')",
}, path)
vim.cmd.source(path)
local sid = vim.g.sess_native_sid
local tabline = require("sess.ui.tabline")
local sidebar = require("sess.ui.sidebar")
fixture.setup()
assert(sidebar.open())
-- Explicit script-local function names retain their original identity on native
-- redraw too, rather than being rebound to the decoration bridge's script.
vim.o.tabline = "%!" .. sid .. "Provider()"
assert(tabline.install())
vim.cmd.redrawtabline()
assert(tabline.heading_visible())
for _, original in ipairs({
    "%!s:Provider()",
    "%!s:label",
    "%{s:label}",
    "%{s:Provider()}",
}) do
    -- Neovim evaluates raw s: references in the ambient script context, not the
    -- last-set option SID. Compare inside that same original script context.
    local before = vim.fn.call(sid .. "Evaluate", { original })
    vim.o.tabline = original
    assert(vim.fn.call(sid .. "Install", {}))
    fixture.equal(original, vim.o.tabline)
    assert(not tabline.heading_visible())
    local after = vim.fn.call(sid .. "Evaluate", { vim.o.tabline })
    fixture.equal(before, after)
end
-- Quoted text is not rewritten or mistaken for a script-local reference.
for _, original in ipairs({
    "%!'literal s:Provider() s:label'",
    '%{"literal s:label"}',
    "literal s:label %%{s:label}",
}) do
    vim.o.tabline = original
    assert(tabline.install())
    assert(vim.o.tabline ~= original)
    local before = vim.fn.call(sid .. "Evaluate", { original })
    local after = vim.fn.call(sid .. "Evaluate", { vim.o.tabline })
    assert(after:find(before, 1, true), original)
end
assert(sidebar.close())
