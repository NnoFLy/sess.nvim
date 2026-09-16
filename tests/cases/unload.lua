fixture.setup()

local api = require("sess.api")
local editor = require("sess.editor")
local storage = require("sess.storage")

local _, _, a = api.session.create(fixture.directory("a"), { name = "Project A" })
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved" })
local _, _, b = api.session.create(fixture.directory("b"))
local bbuf = vim.api.nvim_get_current_buf()

local observed = {}
vim.api.nvim_create_autocmd("User", {
    pattern = { "SessSaved", "SessUnloaded" },
    callback = function(event)
        table.insert(observed, event.match)
        fixture.equal(api.state.current(), event.data.current)
    end,
})

local view = editor.capture()
local previous = api.state.prev()
local snapshots = { storage.read_session(a.id), storage.read_session(b.id) }
local ok, err = api.session.unload(a.id, {
    hooks = {
        before_transition = function(context)
            fixture.equal("unload", context.operation)
            fixture.equal(a.id, context.session.id)
            fixture.equal(b.id, context.current.id)
            error("veto unload")
        end,
    },
})
assert(not ok and err:match("veto unload"))
fixture.equal(2, #api.state.active())

local item, diagnostics
ok, err, item, diagnostics = api.session.unload("project a", {
    confirm = function(request)
        fixture.equal("buffers", request.kind)
        return "discard"
    end,
    hooks = {
        before_transition = function()
            local nested, nested_err = api.session.unload(b)
            assert(not nested and nested_err:match("in progress"))
        end,
        after_operation = function(context)
            fixture.equal("unload", context.operation)
            fixture.equal(a.id, context.session.id)
            fixture.equal(b.id, context.current.id)
            fixture.equal({ api.state.current() }, api.state.active())
            error("observer failure")
        end,
    },
})
assert(ok, err)
fixture.equal(a.id, item.id)
assert(diagnostics[1]:match("observer failure"))
fixture.equal({ "SessUnloaded" }, observed)
view.listing[buf] = nil
fixture.equal(view, editor.capture())
fixture.equal(previous, api.state.prev())
fixture.equal(snapshots, { storage.read_session(a.id), storage.read_session(b.id) })
assert(not vim.api.nvim_buf_is_valid(buf))
fixture.equal(nil, require("sess.state").get_view(a.id))

-- Already detached targets succeed without hooks, saves or events.
ok, err, item, diagnostics = api.session.unload(a, {
    hooks = {
        before_transition = function()
            error("must not run")
        end,
    },
})
assert(ok, err)
fixture.equal({}, diagnostics)
fixture.equal({ "SessUnloaded" }, observed)

-- Returning after unload sources the persisted snapshot, not a stale live view.
assert(api.session.load(a))
assert(buf ~= vim.api.nvim_get_current_buf())
buf = vim.api.nvim_get_current_buf()
fixture.equal("", vim.bo[buf].buftype)
assert(vim.bo[buf].buflisted)
fixture.equal({ "" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
fixture.equal(2, #api.state.active())

-- Snapshot failure prevents teardown; success closes current buffers.
observed = {}
local snapshot = editor.snapshot
editor.snapshot = function()
    return false, "snapshot failed"
end
ok, err = api.session.unload(a.metadata.cwd)
editor.snapshot = snapshot
assert(not ok and err:match("snapshot failed"))
fixture.equal(a.id, api.state.current().id)
fixture.equal(2, #api.state.active())
fixture.equal({}, observed)
assert(api.session.unload(a.metadata.cwd))
fixture.equal({ "SessSaved", "SessUnloaded" }, observed)
fixture.equal(nil, api.state.current())
fixture.equal(a.id, api.state.prev().id)
assert(not vim.api.nvim_buf_is_valid(buf))

-- A hidden session can also be unloaded when there is no current session.
view = editor.capture()
assert(api.session.unload(b))
fixture.equal({}, api.state.active())
view.listing[bbuf] = nil
fixture.equal(view, editor.capture())
fixture.equal(a.id, api.state.prev().id)
assert(not api.session.unload())
assert(not api.session.unload("missing"))
for _, target in ipairs({ false, 1, "", { id = "../escape", metadata = {} } }) do
    assert(not api.session.unload(target))
end

-- Revalidate after hooks before committing runtime state.
assert(api.session.load(b))
assert(api.session.load(a))
local metadata = assert(storage.read_metadata(b.id))
ok, err = api.session.unload(b.id, {
    hooks = {
        before_transition = function()
            assert(storage.delete(b.id, true))
        end,
    },
})
assert(not ok and err:match("not found"))
fixture.equal(2, #api.state.active())
assert(storage.create_with_metadata(b.id, metadata))

-- The old options-only API remains supported.
local called = false
assert(api.session.unload({
    hooks = {
        before_transition = function()
            called = true
        end,
    },
}))
assert(called)
