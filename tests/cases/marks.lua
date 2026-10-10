fixture.setup()

local api = require("sess.api")
local storage = require("sess.storage")
local _, _, first = api.session.create(fixture.directory("first"), { name = "first" })
local _, _, second = api.session.create(fixture.directory("second"), { name = "second" })

local ok, err, entries, diagnostics = api.session.list_marks()
assert(ok, err)
fixture.equal({}, entries)
fixture.equal({}, diagnostics)

ok, err, first, diagnostics = api.session.set_mark(first, "s")
assert(ok, err)
local marked_ok, marked_err, marked = api.session.get_by_mark("s")
assert(marked_ok, marked_err)
fixture.equal(first.id, marked.id)
assert(#diagnostics == 0)
local _, _, listed_marks = api.session.list_marks()
fixture.equal({ "s" }, vim.tbl_map(function(entry) return entry.mark end, listed_marks))

local rejected, conflict = api.session.set_mark(second, "s")
assert(not rejected and conflict:match("already assigned"))
assert(api.session.set_mark(second, "s", { replace = true }))
local replaced_ok, replaced_err, replaced = api.session.get_by_mark("s")
assert(replaced_ok, replaced_err)
fixture.equal(second.id, replaced.id)

local mark_path = fixture.root .. "/store/marks.json"
assert(vim.fn.filereadable(mark_path) == 1)
local broken = fixture.root .. "/store/broken"
vim.fn.mkdir(broken, "p")
local stale_id = "stale-session"
local marks = storage.read_marks()
marks.s = stale_id
assert(storage.write_marks(marks))

-- A mark registry symlink must never be followed or replaced, including when
-- the symlink is dangling.
local outside_marks = fixture.directory("outside_marks") .. "/marks.json"
local outside_content = { vim.json.encode({ version = 1, marks = {} }) }
vim.fn.writefile(outside_content, outside_marks)
assert(vim.uv.fs_unlink(mark_path))
assert(vim.uv.fs_symlink(outside_marks, mark_path))
local linked_marks, linked_err = storage.read_marks()
assert(not linked_marks and tostring(linked_err):match("regular file"), tostring(linked_err))
local linked_write, linked_write_err = storage.write_marks({})
assert(not linked_write and tostring(linked_write_err):match("regular file"), tostring(linked_write_err))
fixture.equal(outside_content, vim.fn.readfile(outside_marks))
assert(vim.uv.fs_unlink(mark_path))
local dangling_target = fixture.root .. "/missing_marks.json"
assert(vim.uv.fs_symlink(dangling_target, mark_path))
local dangling_marks, dangling_err = storage.read_marks()
assert(not dangling_marks and tostring(dangling_err):match("regular file"), tostring(dangling_err))
local dangling_write, dangling_write_err = storage.write_marks({})
assert(not dangling_write and tostring(dangling_write_err):match("regular file"), tostring(dangling_write_err))
assert(vim.uv.fs_unlink(mark_path))
assert(storage.write_marks(marks))

local stale_ok, stale_err, stale_entries, stale_diagnostics = api.session.list_marks()
assert(stale_ok, stale_err)
assert(stale_entries[1].stale)
assert(stale_diagnostics[1]:match("stale mark"))
assert(not api.session.get_by_mark("s"))
assert(api.session.clear_mark("s"))

require("sess.ui.command").setup()
assert(vim.fn.getcompletion("Sess load @", "cmdline")[1] == nil)
assert(vim.fn.getcompletion("Sess unmark @", "cmdline")[1] == nil)
assert(not api.session.set_mark(second, "S"))

assert(api.session.set_mark(first, "x", { replace = true }))
assert(api.session.load(second))
assert(require("sess").goto_mark("@x"))
fixture.equal(first.id, api.state.current().id)
local getcharstr = vim.fn.getcharstr
vim.fn.getcharstr = function() return "x" end
assert(require("sess").goto_mark())
vim.fn.getcharstr = getcharstr
local notify = vim.notify
vim.notify = function() end
assert(not require("sess").goto_mark("xy"))
vim.notify = notify

local messages = {}
vim.notify = function(message, level)
    messages[#messages + 1] = { message = message, level = level }
end
assert(require("sess").goto_mark("m"))
vim.notify = notify
fixture.equal({
    { message = "[sess.nvim] Created mark @m on current session", level = vim.log.levels.INFO },
}, messages)
local created_ok, created_err, created = api.session.get_by_mark("m")
assert(created_ok, created_err)
fixture.equal(first.id, created.id)

vim.fn.getcharstr = function() return "n" end
assert(require("sess").set_mark())
vim.fn.getcharstr = getcharstr
local marked_current_ok, marked_current_err, marked_current = api.session.get_by_mark("n")
assert(marked_current_ok, marked_current_err)
fixture.equal(first.id, marked_current.id)

local events = {}
vim.api.nvim_create_autocmd("User", {
    pattern = { "SessMarked", "SessUnmarked" },
    callback = function(event) events[#events + 1] = event.match end,
})
assert(api.session.set_mark(second, "x", { replace = true }))
assert(api.session.clear_mark("x"))
fixture.equal({ "SessMarked", "SessUnmarked" }, events)
