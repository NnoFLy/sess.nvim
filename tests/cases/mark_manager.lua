fixture.setup()

local api = require("sess.api")
local sess = require("sess")
local storage = require("sess.storage")

local _, _, first = api.session.create(fixture.directory("first"), { name = "first" })
local _, _, second = api.session.create(fixture.directory("second"), { name = "second" })
assert(api.session.set_mark(first, "a"))
assert(api.session.set_mark(second, "q"))
assert(api.session.load(first))

local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
    vim.wait(10)
end

local getcharstr = vim.fn.getcharstr
vim.fn.getcharstr = function() return "\5" end
assert(sess.goto_mark())
vim.fn.getcharstr = getcharstr
local popup = vim.api.nvim_get_current_win()
assert(vim.api.nvim_win_get_config(popup).focusable)
local popup_buf = vim.api.nvim_win_get_buf(popup)
assert(vim.api.nvim_get_option_value("modifiable", { buf = popup_buf }) == false)
local lines = vim.api.nvim_buf_get_lines(popup_buf, 0, -1, false)
assert(lines[1] == "a  first" and lines[2] == "q  second")
local confirm = vim.fn.confirm
vim.fn.confirm = function() return 1 end
local original_input = vim.ui.input
vim.ui.input = function(_, callback) callback("renamed") end

vim.fn.getcharstr = function() return "x" end
feed("r")
assert(not api.session.get_by_mark("a"))
local moved, move_err, moved_item = api.session.get_by_mark("x")
assert(moved, move_err)
assert(moved_item.id == first.id)

feed("u")
local undone, undo_err = api.session.get_by_mark("a")
assert(undone, undo_err)
assert(not api.session.get_by_mark("x"))

feed("<Up>")
feed("d")
assert(not api.session.get_by_mark("a"))
feed("u")
assert(api.session.get_by_mark("a"))
feed("<Up>")

feed("R")
local renamed_ok, rename_err, renamed = api.session.get_by_mark("a")
assert(renamed_ok, rename_err)
assert(rename_err == nil)
assert(renamed.metadata.name == "renamed")

vim.fn.getcharstr = function() return "a" end
feed("g")
vim.fn.getcharstr = getcharstr
vim.fn.confirm = confirm
vim.ui.input = original_input
assert(vim.api.nvim_get_current_win() ~= popup)

-- The lifecycle move is atomic and retains stale owners.
local moved_ok, moved_api_err = api.session.move_mark("a", "b")
assert(moved_ok, moved_api_err)
local marks = storage.read_marks()
marks.b = "missing-owner"
assert(storage.write_marks(marks))
assert(api.session.move_mark("b", "c"))
local stale = storage.read_marks()
assert(stale.b == nil and stale.c == "missing-owner")
