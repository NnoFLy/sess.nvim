fixture.setup()
local api = require("sess.api")
local _, _, item = api.session.create(fixture.directory("project"), { name = "project" })
api.active.snapshot_async = function(callback)
    callback(api.active.initial_snapshot())
end
local sidebar = require("sess.ui.sidebar")
sidebar.configure({ refresh_interval = 60000 })
local function open()
    assert(sidebar.open())
    vim.api.nvim_win_set_cursor(vim.api.nvim_get_current_win(), { 3, 0 })
end
local function key(lhs)
    return vim.fn.maparg(lhs, "n", false, true).callback()
end
open()
local prompts, callback = 0
vim.ui.input = function(_, done)
    prompts = prompts + 1
    callback = done
end
local function name()
    local ok, err, session = api.session.get(item.id)
    assert(ok, err)
    return session.metadata.name
end
key("rr")
local first = callback
key("rr")
key("p")
key("<Tab>")
key("<C-s>")
assert(not sidebar.refresh())
fixture.equal(1, prompts)
first(nil)
fixture.equal("project", name())
key("rr")
callback("   ")
fixture.equal("project", name())
key("rr")
callback(" name | let g:sess_injected = 1 ")
fixture.equal("name | let g:sess_injected = 1", name())
assert(vim.g.sess_injected == nil)
callback("duplicate")
fixture.equal("name | let g:sess_injected = 1", name())

-- Old callbacks must not release a newer prompt's guard after close/reopen.
key("rr")
local old = callback
assert(sidebar.close())
open()
key("rr")
local current = callback
old("stale")
assert(not sidebar.refresh())
current("fresh")
fixture.equal("fresh", name())
first("very late")
fixture.equal("fresh", name())
key("<C-b>")
old = callback
assert(sidebar.close())
open()
old("z")
local _, _, entries = api.session.list_marks()
fixture.equal({}, entries)

-- A disappearing active target is rejected even if its stored record survives.
key("rr")
local vanished = callback
assert(api.session.unload(item.id))
vanished("inactive rename")
fixture.equal("fresh", name())
assert(sidebar.is_open())
assert(api.session.load(item.id))
assert(sidebar.refresh())
vim.api.nvim_set_current_win(vim.fn.bufwinid("Sess Sidebar"))
vim.api.nvim_win_set_cursor(0, { 3, 0 })

-- Throwing prompt providers/callbacks release the pending guard.
vim.ui.input = function()
    error("input provider failed")
end
key("rr")
assert(sidebar.refresh())
vim.ui.input = function(_, done)
    callback = done
end
key("rr")
local original_rename = api.session.rename
api.session.rename = function()
    error("rename callback failed")
end
callback("throw")
api.session.rename = original_rename
assert(sidebar.refresh())
key("<C-b>")
callback("INVALID")
assert(sidebar.refresh())

-- Replacement confirmation cannot mutate after the sidebar has closed.
assert(api.session.set_mark(item.id, "a"))
key("<C-b>")
vim.fn.confirm = function()
    assert(sidebar.close())
    return 1
end
callback("a")
fixture.equal("fresh", name())

-- Late async refresh completion cannot overwrite a reopened instance.
local refresh_done
api.active.snapshot_async = function(done)
    refresh_done = done
    return function() end
end
open()
local late = refresh_done
assert(sidebar.close())
open()
local latest = refresh_done
late({ sessions = {} })
assert(not sidebar.refresh() or sidebar.is_open())
latest(api.active.initial_snapshot())
local session_line = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 2, 3, false)[1]
assert(session_line:find("fresh", 1, true))
-- Refresh exceptions and reported failures both release the refresh guard.
api.active.snapshot_async = function()
    error("refresh provider failed")
end
assert(not sidebar.refresh())
api.active.snapshot_async = function(_, options)
    options.on_error("refresh failed")
end
assert(sidebar.refresh())
api.active.snapshot_async = function(done)
    done(api.active.initial_snapshot())
end
assert(sidebar.refresh())
assert(sidebar.close())
