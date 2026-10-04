fixture.setup()

local editor = require("sess.editor")
local ui2 = { wins = {} }
local previous_ui2 = package.loaded["vim._core.ui2"]
package.loaded["vim._core.ui2"] = ui2

local buf = vim.api.nvim_create_buf(false, true)
local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    row = 1,
    col = 1,
    width = 12,
    height = 3,
})
ui2.wins.cmd = win

local view = editor.capture()
for _, tab in ipairs(view.tabs) do
    assert(#tab.floats == 0, "editor-owned ui2 window was captured")
end

editor.hide()
assert(vim.api.nvim_win_is_valid(win), "editor-owned ui2 window was closed")

ui2.wins.cmd = nil
vim.api.nvim_win_close(win, true)
vim.api.nvim_buf_delete(buf, { force = true })
package.loaded["vim._core.ui2"] = previous_ui2
