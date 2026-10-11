fixture.setup()

local api = require("sess.api")
local path = require("sess.ui.path")

for _, prefix in ipairs({ "./", "../", "~/", "/" }) do
    assert(path.is_path(prefix), "expected path prefix to be recognized: " .. prefix)
end
for _, input in ipairs({ "", "project", "path:project" }) do
    assert(not path.is_path(input), "unexpected path prefix: " .. input)
end

local project = fixture.directory("project with space")
fixture.directory("project with space/child")
fixture.directory("project with space/other")

local parent_entries, parent_err = path.enumerate("../")
assert(not parent_err)
assert(parent_entries[1].is_self)
fixture.equal(vim.fs.normalize(vim.fn.getcwd() .. "/.."), parent_entries[1].path)
fixture.equal("../", parent_entries[1].prompt)

local entries, err = path.enumerate("./project")
assert(not err)
fixture.equal(1, #entries)
fixture.equal(project, entries[1].path)
fixture.equal("./project with space/", entries[1].prompt)

local escaped_entries, escaped_err = path.enumerate("./project\\ with")
assert(not escaped_err)
fixture.equal(project, escaped_entries[1].path)

local children, children_err = path.enumerate("./project with space/")
assert(not children_err)
fixture.equal(3, #children)
fixture.equal("./project with space/", children[1].prompt)
fixture.equal("child", children[2].name)
fixture.equal("other", children[3].name)

vim.notify = function() end
vim.fn.mkdir(vim.fs.joinpath(vim.env.HOME, "completion-home"), "p")
require("sess.ui.command").setup()

for _, prefix in ipairs({ "~/", "./", "../", "/" }) do
    local completions = vim.fn.getcompletion("Sess load " .. prefix, "cmdline")
    assert(#completions > 0, "expected directory completion for " .. prefix)
    assert(not vim.list_contains(completions, prefix), "exact path should not hide siblings: " .. prefix)
end

local matches = vim.fn.getcompletion("Sess load ./project", "cmdline")
assert(vim.list_contains(matches, "./project\\ with\\ space/"))

vim.cmd("Sess load ./project\\ with\\ space")
assert(api.state.current())
fixture.equal(project, api.state.current().metadata.cwd)

local _, _, sessions = api.session.list()
fixture.equal(1, #sessions)

local link = fixture.root .. "/project-link"
local linked, link_err = vim.uv.fs_symlink(project, link)
assert(linked, link_err)
local loaded, load_err = api.session.load(link)
assert(loaded, load_err)
local _, _, linked_sessions = api.session.list()
fixture.equal(1, #linked_sessions)

vim.cmd("Sess load ./project\\ with\\ space")
local _, _, repeated_sessions = api.session.list()
fixture.equal(1, #repeated_sessions)

local ok = require("sess.ui.commands.load")({ args = { "./missing" } })
assert(ok == false)
local _, _, unchanged_sessions = api.session.list()
fixture.equal(1, #unchanged_sessions)

