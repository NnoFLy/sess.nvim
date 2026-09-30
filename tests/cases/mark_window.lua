fixture.setup()

local api = require("sess.api")
local sess = require("sess")
local storage = require("sess.storage")
local first_ok, first_err, first =
    api.session.create(fixture.directory("first"), { name = "first" })
assert(first_ok, first_err)
local second_ok, second_err, second =
    api.session.create(fixture.directory("second"), { name = "second" })
assert(second_ok, second_err)
assert(api.session.set_mark(first, "a"))
assert(api.session.set_mark(second, "q"))
assert(api.session.load(first))

local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
    vim.wait(10)
end

local origin = vim.api.nvim_get_current_win()
assert(sess.goto_mark())
local popup = vim.api.nvim_get_current_win()
local popup_config = vim.api.nvim_win_get_config(popup)
assert(popup_config.relative ~= "")
assert(popup_config.focusable == false)
local popup_buf = vim.api.nvim_win_get_buf(popup)
local lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
assert(lines[1] == "a  first")
assert(lines[2] == "q  second")
local maps = vim.api.nvim_buf_get_keymap(popup_buf, "n")
local mapped = {}
for _, mapping in ipairs(maps) do
    mapped[mapping.lhs] = true
end
assert(mapped.a and mapped.q and mapped.j and mapped.k)
assert(not vim.api.nvim_get_keymap("n")["a"])

feed("z")
assert(vim.api.nvim_get_current_win() == popup)
feed("<Esc>")
assert(vim.api.nvim_get_current_win() == origin)

local marks = storage.read_marks()
marks.q = "missing-session"
assert(storage.write_marks(marks))
assert(sess.goto_mark())
popup = vim.api.nvim_get_current_win()
lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(popup), 0, -1, false)
assert(lines[2]:match("unavailable"))
local notify = vim.notify
vim.notify = function() end
feed("q")
vim.notify = notify
assert(vim.api.nvim_get_current_win() == origin)
local stale = storage.read_marks()
assert(stale.q == "missing-session")
