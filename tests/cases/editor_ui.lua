fixture.setup()

local editor = require("sess.editor")
local ui2 = { wins = {}, bufs = {} }
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
ui2.bufs.cmd = buf
vim.bo[buf].buflisted = true

local mark_buf = vim.api.nvim_create_buf(false, true)
vim.b[mark_buf].sess_mark_window = true
vim.bo[mark_buf].buflisted = true

local view = editor.capture()
assert(not view.buffers[buf], "editor-owned ui2 buffer was captured")
assert(not view.listing[buf], "editor-owned ui2 listing was captured")
assert(not view.buffers[mark_buf], "mark window buffer was captured")
assert(not view.listing[mark_buf], "mark window listing was captured")
for _, tab in ipairs(view.tabs) do
    assert(#tab.floats == 0, "editor-owned ui2 window was captured")
end

local callback_saw_buffer
vim.schedule(function()
    callback_saw_buffer = vim.api.nvim_buf_is_valid(buf)
end)
editor.hide()
assert(callback_saw_buffer, "queued callbacks ran after editor state was hidden")
assert(vim.api.nvim_win_is_valid(win), "editor-owned ui2 window was closed")
assert(vim.bo[buf].buflisted, "editor-owned ui2 buffer was unlisted")
assert(vim.bo[mark_buf].buflisted, "mark window buffer was unlisted")

local first_float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
    relative = "editor",
    row = 1,
    col = 1,
    width = 8,
    height = 2,
})
local second_float = vim.api.nvim_open_win(vim.api.nvim_create_buf(false, true), false, {
    relative = "editor",
    row = 4,
    col = 1,
    width = 8,
    height = 2,
})
vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(first_float),
    once = true,
    callback = function()
        if vim.api.nvim_win_is_valid(second_float) then
            vim.api.nvim_win_close(second_float, true)
        end
    end,
})
assert(pcall(editor.hide), "window teardown should tolerate callback-driven closes")

ui2.wins.cmd = nil
vim.api.nvim_win_close(win, true)
vim.api.nvim_buf_delete(buf, { force = true })
vim.api.nvim_buf_delete(mark_buf, { force = true })
package.loaded["vim._core.ui2"] = previous_ui2
