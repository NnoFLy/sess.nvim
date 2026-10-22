vim.o.tabline = "existing custom tabline"
vim.o.showtabline = 1
assert(require("sess").setup({
    store_path = fixture.root .. "/store",
    smart_auto_load = "none",
    auto_save = false,
    tabline = { enabled = false },
}))
fixture.equal({ enabled = false }, require("sess.api.opts").get().tabline)
fixture.equal("existing custom tabline", vim.o.tabline)
fixture.equal(1, vim.o.showtabline)
