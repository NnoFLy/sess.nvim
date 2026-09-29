fixture.setup()

local api = require("sess.api")
local storage = require("sess.storage")

local project = fixture.directory("project")
local ok, err, item = api.session.create(project, { name = "recoverable" })
assert(ok, err)

local deleted, delete_err = api.session.delete(item)
assert(deleted, delete_err)
assert(api.state.current() == nil)

local listed, list_err, entries = api.session.list_deleted()
assert(listed, list_err)
fixture.equal(1, #entries)
local key = entries[1].key

local restored, restore_err, restored_item = api.session.restore(key)
assert(restored, restore_err)
fixture.equal(item.id, restored_item.id)
fixture.equal(item.metadata, restored_item.metadata)
assert(api.state.current() == nil)
assert(api.state.prev() == nil)
fixture.equal(0, #api.state.active())

listed, list_err, entries = api.session.list_deleted()
assert(listed, list_err)
fixture.equal(0, #entries)
local found, get_err, live = api.session.get_by_id(item.id)
assert(found, get_err)
fixture.equal(item.id, live.id)

-- Trash scans must not turn an unreadable store into a successful empty list.
local readdir = vim.fn.readdir
vim.fn.readdir = function(path)
    if path == storage.root() .. "/trash" then
        error("injected trash read failure")
    end
    return readdir(path)
end

local scanned, scan_err = api.session.list_deleted()
vim.fn.readdir = readdir
assert(not scanned)
assert(scan_err:match("injected trash read failure"), scan_err)

-- Restore rejects metadata that live-session validation would reject, rather
-- than moving an unusable record back into sessions/.
local deleted_again, delete_again_err = api.session.delete(item)
assert(deleted_again, delete_again_err)
listed, list_err, entries = api.session.list_deleted()
assert(listed, list_err)
local metadata_path = storage.root() .. "/trash/" .. entries[1].key .. "/metadata.json"
local metadata = vim.json.decode(table.concat(vim.fn.readfile(metadata_path), "\n"))
metadata.created_at = -1
vim.fn.writefile({ vim.json.encode(metadata) }, metadata_path)

local bad_key = entries[1].key
local diagnostics
listed, list_err, entries, diagnostics = api.session.list_deleted()
assert(listed, list_err)
fixture.equal(0, #entries)
assert(#diagnostics > 0)
local restored_bad, bad_err = api.session.restore(bad_key)
assert(not restored_bad)
assert(bad_err:match("invalid session metadata"), bad_err)
