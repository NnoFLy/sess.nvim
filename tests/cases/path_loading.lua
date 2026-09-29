fixture.setup()

local api = require("sess.api")
local path = require("sess.ui.path")

local project = fixture.directory("project with space")
fixture.directory("project with space/child")
fixture.directory("project with space/other")

local entries, err = path.enumerate("./project")
assert(not err)
fixture.equal(1, #entries)
fixture.equal(project, entries[1].path)
fixture.equal("./project with space/", entries[1].prompt)

local children, children_err = path.enumerate("./project with space/")
assert(not children_err)
fixture.equal(3, #children)
fixture.equal("./project with space/", children[1].prompt)
fixture.equal("child", children[2].name)
fixture.equal("other", children[3].name)

vim.notify = function() end
require("sess.ui.command").setup()
local matches = vim.fn.getcompletion("Sess load ./project", "cmdline")
assert(vim.list_contains(matches, "./project\\ with\\ space/"))

vim.cmd("Sess load ./project\\ with\\ space")
assert(api.state.current())
fixture.equal(project, api.state.current().metadata.cwd)

local _, _, sessions = api.session.list()
fixture.equal(1, #sessions)
vim.cmd("Sess load ./project\\ with\\ space")
local _, _, repeated_sessions = api.session.list()
fixture.equal(1, #repeated_sessions)

local ok = require("sess.ui.commands.load")({ args = { "./missing" } })
assert(ok == false)
local _, _, unchanged_sessions = api.session.list()
fixture.equal(1, #unchanged_sessions)

