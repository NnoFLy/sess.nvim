-- Exercise the compatibility path used when the host has no known
-- no-follow directory-descriptor flags. This test only mocks capability
-- discovery; all filesystem operations remain real.
local original_uname = vim.uv.os_uname
vim.uv.os_uname = function()
    return { sysname = "Windows_NT" }
end

fixture.setup()
vim.uv.os_uname = original_uname
assert(require("sess.api.opts").is_setup(), "storage fallback setup failed")

local storage = require("sess.storage")
local api = require("sess.api")

-- The pathname fallback validates configured-root ancestors, not only the
-- final store directory. A symlinked ancestor must fail closed.
local outside_parent = fixture.directory("outside-parent")
local linked_parent = fixture.root .. "/linked-parent"
assert(vim.uv.fs_symlink(outside_parent, linked_parent))
local rejected, rejected_err = storage.init(linked_parent .. "/store")
assert(not rejected and tostring(rejected_err):match("untrusted"), tostring(rejected_err))
vim.uv.os_uname = function()
    return { sysname = "Windows_NT" }
end
assert(storage.init(fixture.root .. "/store"))
vim.uv.os_uname = original_uname

local ok, err, item = api.session.create(fixture.directory("project"))
assert(ok, tostring(err))

local mkstemp = vim.uv.fs_mkstemp
local temporary_pattern
vim.uv.fs_mkstemp = function(pattern)
    temporary_pattern = pattern
    return mkstemp(pattern)
end

local updated = vim.deepcopy(item.metadata)
updated.name = "fallback-write"
ok, err = storage.write_metadata(item.id, updated)
vim.uv.fs_mkstemp = mkstemp
assert(ok, tostring(err))
assert(temporary_pattern and not temporary_pattern:match("/fd/%d+/"), "unexpected descriptor temporary path")
fixture.equal(updated, storage.read_metadata(item.id))

ok, err = storage.write_session(item.id, "let SessionLoad = 1\nunlet SessionLoad\n")
assert(ok, tostring(err))
local snapshot, snapshot_err = storage.read_session(item.id)
assert(snapshot, tostring(snapshot_err))
assert(snapshot:match("SessionLoad"), "snapshot contents missing")
