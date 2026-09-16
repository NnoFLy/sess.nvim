fixture.setup()

local api = require("sess.api")
local editor = require("sess.editor")
local storage = require("sess.storage")

local _, _, a = api.session.create(fixture.directory("a"))
local _, _, b = api.session.create(fixture.directory("b"))
assert(api.session.load(a))

local path = assert(storage.get_session_path(b.id))
local original = assert(storage.read_session(b.id))
vim.uv.fs_unlink(path)

local before = assert(storage.read_session(a.id))
local ok, err = api.session.load(b)
assert(not ok and err:match("not readable"))
fixture.equal(before, storage.read_session(a.id))
assert(storage.write_session(b.id, original))

local function reentrant()
    local nested, nested_err = api.session.load(b)
    assert(not nested and nested_err:match("in progress"))
end

assert(
    api.session.load(b, { hooks = { before_transition = reentrant, after_operation = reentrant } })
)
assert(api.session.load(a))
ok, err = api.session.load(b, {
    hooks = {
        before_transition = function()
            vim.uv.fs_unlink(path)
        end,
    },
})

assert(not ok and err:match("not readable"))
fixture.equal(a.id, api.state.current().id)
assert(storage.write_session(b.id, original))

-- Build mixed cwd scopes, then fail after a destructive view change.
local global = fixture.directory("global")
local tabcwd = fixture.directory("tab")
local windowcwd = fixture.directory("window")
vim.cmd.cd(global)
vim.cmd.tcd(tabcwd)
vim.cmd("split")
vim.cmd.lcd(windowcwd)
vim.cmd("tabnew")
vim.cmd.lcd(a.metadata.cwd)
vim.cmd("tabprevious")

local view = editor.capture()
local load = editor.load
editor.load = function()
    editor.empty(b.metadata.cwd)
    error("injected transition failure")
end

ok, err = api.session.load(b)
editor.load = load
assert(not ok and err:match("injected transition failure"))
fixture.equal(a.id, api.state.current().id)

local restored = editor.capture()
fixture.equal(view.cwd, restored.cwd)
fixture.equal(#view.tabs, #restored.tabs)

for i, tab in ipairs(view.tabs) do
    fixture.equal(tab.cwd, restored.tabs[i].cwd)

    local function window_dirs(t)
        local dirs = {}

        for _, w in pairs(t.windows) do
            table.insert(dirs, w.cwd or "global-or-tab")
        end

        table.sort(dirs)

        return dirs
    end

    fixture.equal(window_dirs(tab), window_dirs(restored.tabs[i]))
end

for buf, listed in pairs(view.listing) do
    fixture.equal(listed, vim.bo[buf].buflisted)
end

-- Unexpected exceptions release the guard; same-session loads don't run hooks.
local snapshot = editor.snapshot
editor.snapshot = function()
    error("unexpected")
end

ok, err = api.session.save()
editor.snapshot = snapshot
assert(not ok and err:match("unexpected"))
assert(api.session.save())

local sessions_before = select(3, api.session.list())

-- Let the outgoing save succeed, then fail the new session's snapshot.
editor.snapshot = function(item)
    if item.id == a.id then
        return snapshot(item)
    end

    return false, "create snapshot failed"
end

ok, err = api.session.create(fixture.directory("failed-create"))
editor.snapshot = snapshot
assert(not ok and err:match("create snapshot failed"))
fixture.equal(a.id, api.state.current().id)
fixture.equal(#sessions_before, #select(3, api.session.list()))

local touch = require("sess.session").touch
require("sess.session").touch = function()
    error("metadata write failed")
end

local diagnostics
ok, err, _, diagnostics = api.session.save()
assert(ok, err)
assert(diagnostics[1]:match("metadata write failed"))
require("sess.session").touch = touch
assert(api.session.load(a, {
    hooks = {
        before_transition = function()
            error("must not run")
        end,
    },
}))

-- A partially executed cold snapshot can only receive best-effort cleanup.
require("sess.state").set_view(b.id, nil)
assert(storage.write_session(b.id, "let g:sess_partial_effect = 1\nthrow 'source failure'\n"))
ok, err = api.session.load(b)
assert(not ok and err:match("source failure"))
fixture.equal(a.id, api.state.current().id)
fixture.equal(1, vim.g.sess_partial_effect)
assert(storage.write_session(b.id, original))
assert(api.session.load(b))
