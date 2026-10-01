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
local getcharstr = vim.fn.getcharstr
local function set_input(value)
    vim.fn.getcharstr = type(value) == "function" and value or function()
        return value
    end
end
local popup_seen_before_input = false
set_input(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if win ~= origin and vim.api.nvim_win_get_config(win).relative ~= "" then
            popup_seen_before_input = true
            assert(vim.api.nvim_get_current_win() == origin)
        end
    end
    return "\5"
end)
assert(sess.goto_mark())
assert(popup_seen_before_input)
vim.fn.getcharstr = getcharstr
local popup = vim.api.nvim_get_current_win()
local popup_config = vim.api.nvim_win_get_config(popup)
assert(popup_config.relative ~= "")
assert(popup_config.focusable == true)
local popup_buf = vim.api.nvim_win_get_buf(popup)
local lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
assert(lines[1] == "a  first")
assert(lines[2] == "q  second")
local maps = vim.api.nvim_buf_get_keymap(popup_buf, "n")
local mapped = {}
for _, mapping in ipairs(maps) do
    mapped[mapping.lhs] = true
end
assert(mapped.g and mapped.d and mapped.u and mapped.r and mapped.R)
assert(not vim.api.nvim_get_keymap("n")["a"])

feed("z")
assert(vim.api.nvim_get_current_win() == popup)
feed("<Esc>")
assert(vim.api.nvim_get_current_win() == origin)

local marks = storage.read_marks()
marks.q = "missing-session"
assert(storage.write_marks(marks))
set_input("\5")
assert(sess.goto_mark())
vim.fn.getcharstr = getcharstr
popup = vim.api.nvim_get_current_win()
lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(popup), 0, -1, false)
assert(lines[2]:match("unavailable"))
local notify = vim.notify
vim.notify = function() end
set_input("q")
feed("g")
vim.fn.getcharstr = getcharstr
vim.notify = notify
assert(vim.api.nvim_get_current_win() == origin)
local stale = storage.read_marks()
assert(stale.q == "missing-session")
