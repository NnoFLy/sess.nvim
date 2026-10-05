fixture.setup()

local api = require("sess.api")
local editor = require("sess.editor")
local storage = require("sess.storage")

-- Omitted public targets resolve the live current session and fail clearly
-- before one exists.
local ok, err = api.session.resolve()
assert(not ok and err == "no current session")
local _, _, first = api.session.create(fixture.directory("first"))
local local_first
ok, err, local_first = api.session.resolve()
assert(ok, err)
fixture.equal(first.id, local_first.id)

local renamed
ok, err, renamed = api.session.rename(nil, "renamed")
assert(ok, err)
fixture.equal(first.id, renamed.id)

-- A current live session remains loadable when its persisted snapshot is gone.
local snapshot_path = assert(storage.get_session_path(first.id))
assert(vim.fn.delete(snapshot_path) == 0)
ok, err = api.session.load()
assert(ok, err)
fixture.equal(first.id, api.state.current().id)

-- Explicit false/error returns from protected editor actions abort transitions.
local protected_ok, protected_err = editor.protected(function()
    return false, "explicit editor failure"
end)
assert(not protected_ok and protected_err:match("explicit editor failure"))
local _, _, second = api.session.create(fixture.directory("second"))
local original_load = editor.load
editor.load = function()
    return false, "injected editor load failure"
end
ok, err = api.session.load(first)
editor.load = original_load
assert(not ok and err:match("injected editor load failure"))
fixture.equal(second.id, api.state.current().id)

-- A valid deleted record retains diagnostics for unrelated corrupt trash.
assert(api.session.delete(first))
local bad_trash = storage.root() .. "/trash/bad-entry"
assert(vim.fn.mkdir(bad_trash, "p") == 1)
local restored, restore_err, restored_item, diagnostics = api.session.restore(first.id)
assert(restored, restore_err)
fixture.equal(first.id, restored_item.id)
assert(#diagnostics > 0 and table.concat(diagnostics, " "):match("bad%-entry"))
local bad_count = 0
for _, diagnostic in ipairs(diagnostics) do
    if diagnostic:match("bad%-entry") then
        bad_count = bad_count + 1
    end
end
assert(bad_count == 1)

-- A snapshot leaf symlink is rejected before any executable content is read.
local _, _, third = api.session.create(fixture.directory("third"))
assert(api.session.load(second))
local third_path = assert(storage.get_session_path(third.id))
local outside_leaf = fixture.directory("outside_leaf") .. "/session.vim"
vim.fn.writefile({ "let g:sess_leaf_attack = 1" }, outside_leaf)
assert(vim.fn.delete(third_path) == 0)
assert(vim.uv.fs_symlink(outside_leaf, third_path))
ok, err = api.session.load(third)
assert(not ok and err:match("not readable"))
assert(api.state.current().id == second.id)
assert(vim.fn.delete(third_path) == 0)
assert(storage.delete(third.id, true))

-- Snapshot generation must use the securely-created inode. Replacing the
-- temporary leaf before :mksession must not write an outside target.
local _, _, fourth = api.session.create(fixture.directory("fourth"))
local outside_snapshot = fixture.directory("outside_snapshot") .. "/session.vim"
local outside_snapshot_content = { "outside-before" }
vim.fn.writefile(outside_snapshot_content, outside_snapshot)
local generated_fd
ok, err = storage.replace_snapshot(fourth.id, function(path, fd)
    generated_fd = fd
    if fd then
        assert(vim.uv.fs_unlink(path))
        assert(vim.uv.fs_symlink(outside_snapshot, path))
    end
    return editor.write_snapshot(path, fourth, fd)
end)
if generated_fd then
    assert(not ok and tostring(err):match("replaced"), tostring(err))
    fixture.equal(outside_snapshot_content, vim.fn.readfile(outside_snapshot))
else
    assert(ok, tostring(err))
end
assert(api.session.load(second))
assert(storage.delete(fourth.id, true))

-- Live owners block acquisition; dead owners are recovered.
local lock_path = storage.root() .. "/.create.lock"
local owner_path = lock_path .. "/owner.json"
assert(vim.fn.mkdir(lock_path, "p") == 1)
vim.fn.writefile({ vim.json.encode({ pid = vim.uv.getpid(), token = "live" }) }, owner_path)
local live_result, live_err = storage.with_create_lock(function() return true end)
assert(not live_result and live_err:match("already in progress"))
-- Exercise the foreign-PID probe as well as the same-process fast path.
local foreign_job = vim.fn.jobstart({ "sleep", "30" })
local foreign_pid = foreign_job > 0 and vim.fn.jobpid(foreign_job) or -1
if foreign_pid > 0 then
    vim.fn.delete(lock_path, "rf")
    assert(vim.fn.mkdir(lock_path, "p") == 1)
    vim.fn.writefile({ vim.json.encode({ pid = foreign_pid, token = "foreign-live" }) }, owner_path)
    local foreign_result, foreign_err = storage.with_create_lock(function() return true end)
    assert(not foreign_result and foreign_err:match("already in progress"))
    vim.fn.jobstop(foreign_job)
end
assert(vim.fn.delete(lock_path, "rf") == 0)
-- EPERM is inconclusive, not evidence that a foreign owner is dead.
local original_kill = vim.uv.kill
vim.uv.kill = function(pid, signal)
    if pid == 424242 then
        return nil, "EPERM: operation not permitted"
    end
    return original_kill(pid, signal)
end
assert(vim.fn.mkdir(lock_path, "p") == 1)
vim.fn.writefile({ vim.json.encode({ pid = 424242, token = "inaccessible-live" }) }, owner_path)
local inaccessible_result, inaccessible_err = storage.with_create_lock(function() return true end)
vim.uv.kill = original_kill
assert(not inaccessible_result and inaccessible_err:match("already in progress"))
assert(vim.fn.delete(lock_path, "rf") == 0)
assert(vim.fn.mkdir(lock_path, "p") == 1)
vim.fn.writefile({ vim.json.encode({ pid = 99999999, token = "dead" }) }, owner_path)
assert(storage.with_create_lock(function() return true end))

-- A fresh lock without an owner is never stolen while publication may still
-- belong to a live process.
assert(vim.fn.mkdir(lock_path, "p") == 1)
local unpublished, unpublished_err = storage.with_create_lock(function() return true end)
assert(not unpublished and unpublished_err:match("owner"))
assert(vim.fn.delete(lock_path, "rf") == 0)

-- A release failure does not discard a committed result and leaves a
-- recoverable tombstone for the next owner.
local original_rmdir = vim.uv.fs_rmdir
vim.uv.fs_rmdir = function(path)
    if path == lock_path then
        return false, "injected release failure"
    end
    return original_rmdir(path)
end
local committed, _, _, release_diagnostic = storage.with_create_lock(function()
    return "committed"
end)
vim.uv.fs_rmdir = original_rmdir
assert(committed == "committed" and release_diagnostic:match("release"))
assert(storage.with_create_lock(function() return true end))

local original_unlink = vim.uv.fs_unlink
local inject_unlink_failure = true
vim.uv.fs_unlink = function(path)
    if path == owner_path and inject_unlink_failure then
        inject_unlink_failure = false
        return false, "injected unlink failure"
    end
    return original_unlink(path)
end
local committed_unlink, _, _, unlink_diagnostic = storage.with_create_lock(function()
    return "committed-unlink"
end)
vim.uv.fs_unlink = original_unlink
assert(committed_unlink == "committed-unlink" and unlink_diagnostic:match("release"))
assert(storage.with_create_lock(function() return true end))

-- A successful public create preserves the cleanup warning exactly once.
local original_rmdir_for_create = vim.uv.fs_rmdir
vim.uv.fs_rmdir = function(path)
    if path == lock_path then
        return false, "injected create release failure"
    end
    return original_rmdir_for_create(path)
end
local create_ok, create_err, _, create_diagnostics = api.session.create(fixture.directory("diagnostic"), {
    name = "diagnostic",
})
vim.uv.fs_rmdir = original_rmdir_for_create
assert(create_ok, create_err)
local create_warning_count = 0
for _, diagnostic in ipairs(create_diagnostics or {}) do
    if diagnostic:match("injected create release failure") then
        create_warning_count = create_warning_count + 1
    end
end
assert(create_warning_count == 1)
assert(storage.with_create_lock(function() return true end))

-- A successful public restore preserves the lock-release warning exactly once.
local _, _, restore_target = api.session.create(fixture.directory("restore_diagnostic"))
assert(api.session.delete(restore_target))
local deleted_listed, deleted_list_err, deleted_restore_entries = api.session.list_deleted()
assert(deleted_listed, deleted_list_err)
local deleted_restore_key
for _, deleted_entry in ipairs(deleted_restore_entries) do
    if deleted_entry.id == restore_target.id then
        deleted_restore_key = deleted_entry.key
        break
    end
end
assert(deleted_restore_key)
local original_rmdir_for_restore = vim.uv.fs_rmdir
vim.uv.fs_rmdir = function(path)
    if path == lock_path then
        return false, "injected restore release failure"
    end
    return original_rmdir_for_restore(path)
end
local restore_ok, restore_failure, _, restore_diagnostics = api.session.restore(deleted_restore_key)
vim.uv.fs_rmdir = original_rmdir_for_restore
assert(restore_ok, restore_failure)
local restore_warning_count = 0
for _, diagnostic in ipairs(restore_diagnostics or {}) do
    if diagnostic:match("injected restore release failure") then
        restore_warning_count = restore_warning_count + 1
    end
end
assert(restore_warning_count == 1)
assert(storage.with_create_lock(function() return true end))

-- Failed callbacks keep the primary error and append release failure exactly
-- once, including when reached through public create and restore.
local function inject_lock_release_failure(label)
    local rmdir = vim.uv.fs_rmdir
    vim.uv.fs_rmdir = function(path)
        if path == lock_path then
            return false, label
        end
        return rmdir(path)
    end
    return function() vim.uv.fs_rmdir = rmdir end
end
local restore_rmdir = inject_lock_release_failure("injected callback release failure")
local callback_result, callback_err = storage.with_create_lock(function()
    return nil, "injected callback failure"
end)
restore_rmdir()
assert(not callback_result and callback_err:match("injected callback failure"), tostring(callback_err))
assert(select(2, callback_err:gsub("injected callback release failure", "")) == 1)
assert(storage.with_create_lock(function() return true end))

restore_rmdir = inject_lock_release_failure("injected failed create release")
local original_create_with_metadata = storage.create_with_metadata
storage.create_with_metadata = function()
    return false, "injected create callback failure"
end
local catalog = require("sess.session")
local failed_create, failed_create_err, _, failed_create_diagnostics = catalog.create({
    cwd = fixture.directory("failed_create"),
    id = "failed_create",
})
storage.create_with_metadata = original_create_with_metadata
restore_rmdir()
assert(not failed_create and failed_create_err:match("injected create callback failure"), tostring(failed_create_err))
assert(select(2, failed_create_err:gsub("injected failed create release", "")) == 1)
for _, diagnostic in ipairs(failed_create_diagnostics or {}) do
    assert(not diagnostic:match("injected failed create release"))
end
assert(storage.with_create_lock(function() return true end))

local _, _, failed_restore_target = api.session.create(fixture.directory("failed_restore"))
assert(api.session.delete(failed_restore_target))
local deleted_entries = select(3, api.session.list_deleted())
local failed_restore_key
for _, entry in ipairs(deleted_entries) do
    if entry.id == failed_restore_target.id then
        failed_restore_key = entry.key
        break
    end
end
assert(failed_restore_key)
assert(api.session.create(fixture.directory("restore_conflict"), { name = failed_restore_target.metadata.name }))
restore_rmdir = inject_lock_release_failure("injected failed restore release")
local failed_restore, failed_restore_err, _, failed_restore_diagnostics = api.session.restore(failed_restore_key)
restore_rmdir()
assert(not failed_restore and failed_restore_err:match("session name already exists"), tostring(failed_restore_err))
assert(select(2, failed_restore_err:gsub("injected failed restore release", "")) == 1)
for _, diagnostic in ipairs(failed_restore_diagnostics or {}) do
    assert(not diagnostic:match("injected failed restore release"))
end
assert(storage.with_create_lock(function() return true end))

-- Keep the early close-failure regression, then reach the final snapshot
-- close after successful generation and verify that a failed handle is retried.
local original_close = vim.uv.fs_close
local close_calls = 0
vim.uv.fs_close = function()
    close_calls = close_calls + 1
    return false, "injected close failure"
end
local generated = false
ok, err = storage.replace_snapshot(second.id, function()
    generated = true
end)
vim.uv.fs_close = original_close
assert(not ok and err:match("injected close failure"))
assert(not generated and close_calls >= 1)
assert(storage.init(storage.root())) -- retry the failed directory close

local original_snapshot = assert(storage.read_session(second.id))
local temporary_fd
local failed_closes = 0
vim.uv.fs_close = function(fd)
    if fd == temporary_fd then
        failed_closes = failed_closes + 1
        return false, "injected final snapshot close failure"
    end
    return original_close(fd)
end
ok, err = storage.replace_snapshot(second.id, function(_, fd)
    temporary_fd = fd
    assert(vim.uv.fs_write(fd, "generated snapshot", -1))
    return true
end)
vim.uv.fs_close = original_close
assert(temporary_fd and not ok and err:match("injected final snapshot close failure"), tostring(err))
assert(failed_closes == 3, "close failure was not retried a bounded number of times")
fixture.equal(original_snapshot, storage.read_session(second.id))
assert(storage.init(storage.root())) -- retry the still-open temporary descriptor

-- Repeated close failures retain handles without unbounded growth. Once the
-- bounded queue is full, operations fail before opening another descriptor;
-- restoring close then lets initialization drain every retained handle.
local repeated_metadata = assert(storage.read_metadata(second.id))
repeated_metadata.name = "repeated-close-failure"
local repeated_close = vim.uv.fs_close
local repeated_close_calls = 0
vim.uv.fs_close = function()
    repeated_close_calls = repeated_close_calls + 1
    return false, "injected repeated close failure"
end
local queue_full_seen = false
for _ = 1, 20 do
    local repeated_ok, repeated_err = storage.write_metadata(second.id, repeated_metadata)
    assert(not repeated_ok)
    queue_full_seen = queue_full_seen or tostring(repeated_err):match("cleanup queue is full") ~= nil
end
assert(queue_full_seen, "descriptor cleanup queue never reported its bound")
assert(repeated_close_calls <= 8 * 3, "descriptor close retries exceeded the bound")

-- Saturation must not make the persistent root descriptor unreachable. The
-- failed switch retains it outside the full retry queue, and the next init
-- retries it exactly through the normal ownership path.
local saturated_root = storage.root()
local saturated_next_root = fixture.directory("saturated_next_store")
ok, err = storage.init(saturated_next_root)
assert(not ok and err:match("retained for retry"), tostring(err))
fixture.equal(saturated_root, storage.root())
vim.uv.fs_close = repeated_close
assert(storage.init(saturated_root))

-- A failed final parent close is reported even after the rename committed.
local original_mkstemp = vim.uv.fs_mkstemp
local parent_fd
vim.uv.fs_mkstemp = function(pattern)
    parent_fd = tonumber(pattern:match("/fd/(%d+)/"))
    return original_mkstemp(pattern)
end
vim.uv.fs_close = function(fd)
    if fd == parent_fd then
        return false, "injected final parent close failure"
    end
    return original_close(fd)
end
ok, err = storage.replace_snapshot(second.id, function(_, fd)
    assert(vim.uv.fs_write(fd, "committed snapshot", -1))
    return true
end)
vim.uv.fs_close = original_close
vim.uv.fs_mkstemp = original_mkstemp
assert(parent_fd and not ok and err:match("injected final parent close failure"), tostring(err))
fixture.equal("committed snapshot", storage.read_session(second.id))
assert(storage.init(storage.root())) -- retry the still-open parent descriptor

-- Root close failure cannot discard the active root or switch storage roots.
local previous_root = storage.root()
vim.uv.fs_close = function()
    return false, "injected root close failure"
end
local next_root = fixture.directory("next_store")
ok, err = storage.init(next_root)
vim.uv.fs_close = original_close
assert(not ok and err:match("injected root close failure"), tostring(err))
fixture.equal(previous_root, storage.root())
assert(storage.init(previous_root))

-- Creation uses an atomic reservation rather than a scan-only uniqueness check.
local lock_result = storage.with_create_lock(function()
    local nested, nested_err = storage.with_create_lock(function() end)
    assert(not nested and nested_err:match("already in progress"))
    return true
end)
assert(lock_result)

-- The store layout rejects a sessions symlink rather than traversing it.
local outside = fixture.directory("outside")
local sessions_path = storage.root() .. "/sessions"
assert(vim.fn.delete(sessions_path, "rf") == 0)
assert(vim.uv.fs_symlink(outside, sessions_path))
local listed, list_err = storage.list()
assert(#listed == 0 and list_err:match("untrusted"))
assert(vim.uv.fs_lstat(outside).type == "directory")
