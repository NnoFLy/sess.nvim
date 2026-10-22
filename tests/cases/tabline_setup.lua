local sess = require("sess")
local opts = require("sess.api.opts")
vim.notify = function() end
vim.o.tabline = "existing custom tabline"
vim.o.showtabline = 0

local invalid = {
    { false, "tabline must be a table" },
    { "native", "tabline must be a table" },
    { { unknown = true }, "unknown tabline option: unknown" },
    { { enabled = "true" }, "tabline.enabled must be boolean" },
    { { enabled = 1 }, "tabline.enabled must be boolean" },
    { { ui = true }, "unknown tabline option: ui" },
    { { enabled = false, ui = false }, "unknown tabline option: ui" },
}
for _, case in ipairs(invalid) do
    local ok, err = sess.setup({ store_path = fixture.root .. "/store", tabline = case[1] })
    assert(not ok)
    fixture.equal(case[2], err)
    assert(not opts.is_setup())
    fixture.equal("existing custom tabline", vim.o.tabline)
    fixture.equal(0, vim.o.showtabline)
    assert(vim.fn.isdirectory(fixture.root .. "/store") == 0)
    assert(vim.fn.maparg("<C-q>", "n") == "")
end

vim.o.tabline = ""
fixture.setup()
fixture.equal({ enabled = true }, opts.get().tabline)
assert(vim.o.tabline ~= "")
fixture.equal(0, vim.o.showtabline)
local rendered = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
assert(rendered:find("1: [No Name]", 1, true), rendered)

-- Public setup remains one-shot and cannot opt out after installing the provider.
local expression = vim.o.tabline
local ok, err = sess.setup({ tabline = { enabled = false } })
assert(not ok)
fixture.equal("sess.nvim is already loaded", err)
fixture.equal(expression, vim.o.tabline)
fixture.equal(0, vim.o.showtabline)
