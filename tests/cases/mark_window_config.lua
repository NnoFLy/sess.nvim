local opts = require("sess.api.opts")
local storage_path = fixture.root .. "/should-not-exist"

local ok, err = opts.setup({
    store_path = storage_path,
    mark_window = { win_options = { unknown = true } },
})
assert(not ok and err:match("unknown"))
assert(vim.fn.isdirectory(storage_path) == 0)

assert(opts.setup({
    store_path = fixture.root .. "/store",
    smart_auto_load = false,
    auto_save = false,
    mark_window = {
        position = "left_top",
        win_options = { cursorline = false },
    },
}))
local configured = opts.get()
assert(configured.mark_window.position == "left_top")
assert(configured.mark_window.width == 48)
assert(configured.mark_window.win_options.cursorline == false)
configured.mark_window.win_options.cursorline = true
assert(opts.get().mark_window.win_options.cursorline == false)
