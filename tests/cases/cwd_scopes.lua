fixture.setup()

local api = require("sess.api")
local editor = require("sess.editor")

local ok, err, a = api.session.create(fixture.directory("a"))
assert(ok, err)

local global = fixture.directory("global")
local tabcwd = fixture.directory("tab")
local windowcwd = fixture.directory("window")
vim.cmd.cd(global)
vim.cmd.tcd(tabcwd)
vim.cmd.lcd(windowcwd)
vim.cmd("tabnew")
vim.cmd.cd(global)
vim.cmd("tabfirst")

local before = editor.capture()
local b
ok, err, b = api.session.create(fixture.directory("b"))
assert(ok, err)
assert(api.session.load(a))

local after = editor.capture()
fixture.equal(before.cwd, after.cwd)
fixture.equal(#before.tabs, #after.tabs)

for i, tab in ipairs(before.tabs) do
    fixture.equal(tab.cwd, after.tabs[i].cwd)

    for _, win in pairs(after.tabs[i].windows) do
        local expected = i == 1 and windowcwd or nil
        fixture.equal(expected, win.cwd)
    end
end

assert(api.session.load(b))
assert(api.session.load(a))
fixture.equal(global, vim.fn.getcwd(-1, 2))
