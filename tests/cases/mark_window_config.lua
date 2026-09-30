local opts = require("sess.api.opts")
local storage_path = fixture.root .. "/should-not-exist"

local ok, err = opts.setup({
    store_path = storage_path,
    mark_window = { win_options = { unknown = true } },
})
assert(not ok and err:match("unknown"))
assert(vim.fn.isdirectory(storage_path) == 0)

local invalid_keymap, invalid_keymap_err = opts.setup({
    store_path = fixture.root .. "/invalid-keymap",
    mark_window = { keymap = { delete = "" } },
})
assert(not invalid_keymap and invalid_keymap_err:match("keymap"))
assert(vim.fn.isdirectory(fixture.root .. "/invalid-keymap") == 0)

local conflicting, conflicting_err = opts.setup({
    store_path = fixture.root .. "/conflicting-keymap",
    mark_window = { keymap = { delete = "u" } },
})
assert(not conflicting and conflicting_err:match("conflict"))
assert(vim.fn.isdirectory(fixture.root .. "/conflicting-keymap") == 0)

assert(opts.setup({
    store_path = fixture.root .. "/store",
    smart_auto_load = false,
    auto_save = false,
    mark_window = {
        position = "left_top",
        win_options = { cursorline = false },
        keymap = { open = "<C-y>" },
    },
}))
local configured = opts.get()
assert(configured.mark_window.position == "left_top")
assert(configured.mark_window.width == 48)
assert(configured.mark_window.win_options.cursorline == false)
assert(configured.mark_window.keymap.open == "<C-y>")
assert(configured.mark_window.keymap.delete == "d")
configured.mark_window.win_options.cursorline = true
assert(opts.get().mark_window.win_options.cursorline == false)
