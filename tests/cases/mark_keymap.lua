fixture.setup()

local api = require("sess.api")
local sess = require("sess")

local first_ok, first_err, first =
    api.session.create(fixture.directory("first"), { name = "first" })
assert(first_ok, first_err)
local second_ok, second_err, second =
    api.session.create(fixture.directory("second"), { name = "second" })
assert(second_ok, second_err)
assert(api.session.set_mark(first, "a"))
assert(api.session.load(second))

local function feed(keys)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
    vim.wait(10)
end

local getcharstr = vim.fn.getcharstr
local function input(value)
    vim.fn.getcharstr = function()
        return value
    end
end

input("a")
feed("<C-q>")
assert(api.state.current().id == first.id)

input("b")
feed("<C-q><C-q>")
local marked_ok, marked_err, marked = api.session.get_by_mark("b")
assert(marked_ok, marked_err)
assert(marked.id == first.id)

vim.fn.getcharstr = function()
    error("edit mapping should not read another key")
end
feed("<C-q><C-e>")
assert(vim.api.nvim_win_get_config(vim.api.nvim_get_current_win()).relative ~= "")
feed("<Esc>")

vim.fn.getcharstr = getcharstr
