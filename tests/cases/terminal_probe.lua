local probe = require("sess.agent.terminal_probe")

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "\27]0;old title\7\27[31mstartup\27[0m",
    "transcript",
    "\27[2K› \27]2;\27[31mcurrent title\27[0m\7",
    "answer",
    "",
    "   ",
})

local screen = probe.snapshot(bufnr)
assert(screen.complete)
assert(screen.bufnr == bufnr)
assert(type(screen.changedtick) == "number")
assert(screen.error == nil)
assert(screen.osc_title == "current title")
assert(vim.deep_equal(screen.top_lines, { "startup", "transcript", "› ", "answer" }))
assert(vim.deep_equal(screen.bottom_lines, { "startup", "transcript", "› ", "answer" }))
assert(vim.deep_equal(screen.current_prompt_lines, { "answer" }))
assert(#screen.recent_lines == 6 and screen.recent_lines[6] == "   ")
assert(vim.deep_equal(probe.lines(bufnr), screen.bottom_lines))

local long = string.rep("x", 2000)
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "❯ " .. long })
screen = probe.snapshot(bufnr)
assert(screen.complete)
assert(#screen.bottom_lines == 1 and #screen.bottom_lines[1] <= 1000)
assert(#screen.current_prompt_lines == 1 and #screen.current_prompt_lines[1] <= 1000)

local original_get_lines = vim.api.nvim_buf_get_lines
vim.api.nvim_buf_get_lines = function()
    return { "safe", 42 }
end
local malformed = probe.snapshot(bufnr)
vim.api.nvim_buf_get_lines = original_get_lines
assert(not malformed.complete)
assert(type(malformed.error) == "string" and #malformed.error > 0)
assert(#malformed.error <= 1000)
assert(#malformed.bottom_lines == 0 and #malformed.recent_lines == 0)

local missing = probe.snapshot(-1)
assert(not missing.complete)
assert(type(missing.error) == "string" and #missing.error > 0)
assert(#missing.bottom_lines == 0 and #missing.recent_lines == 0)
