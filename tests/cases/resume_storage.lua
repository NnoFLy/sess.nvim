local storage = require("sess.storage")
assert(storage.init(fixture.root .. "/store"))

-- Resume history is independent of session snapshots and preserves recorded order.
local ok, err, record = storage.read_resume()
assert(ok, err)
fixture.equal(nil, record)
local previous = { version = 1, active_ids = { "beta", "alpha" }, current_id = "alpha" }
assert(storage.write_resume(previous))
ok, err, record = storage.read_resume()
assert(ok, err)
fixture.equal(previous, record)
record.active_ids[1] = "not_persisted"
local _, _, reread = storage.read_resume()
fixture.equal(previous, reread)

assert(storage.write_resume({ version = 1, active_ids = {} }))
ok, err, record = storage.read_resume()
assert(ok, err)
fixture.equal({ version = 1, active_ids = {} }, record)

-- Untrusted documents are rejected without deleting or repairing the bytes.
local resume_path = fixture.root .. "/store/resume.json"
local malformed = {
    "not JSON",
    "[]",
    '{"version":2,"active_ids":[]}',
    '{"version":1,"active_ids":{}}',
    '{"version":1,"active_ids":["alpha","alpha"]}',
    '{"version":1,"active_ids":["../outside"]}',
    '{"version":1,"active_ids":[17]}',
    '{"version":1,"active_ids":[],"current_id":"alpha"}',
    '{"version":1,"active_ids":["alpha"],"current_id":null}',
    '{"version":1,"active_ids":[],"snapshot":"/outside/session.vim"}',
}
for _, document in ipairs(malformed) do
    vim.fn.writefile({ document }, resume_path)
    ok, err, record = storage.read_resume()
    assert(not ok and type(err) == "string", document)
    fixture.equal(nil, record)
    ok, err = storage.write_resume(previous)
    assert(not ok and type(err) == "string", document)
    fixture.equal({ document }, vim.fn.readfile(resume_path))
end
assert(vim.uv.fs_unlink(resume_path))
assert(storage.write_resume(previous))
local original = vim.fn.readfile(resume_path)
local invalid_inputs = {
    { version = 1, active_ids = { "alpha", "alpha" } },
    { version = 1, active_ids = { [1] = "alpha", [3] = "beta" } },
    { version = 1, active_ids = { "alpha", extra = "beta" } },
    { version = 1, active_ids = { "alpha" }, current_id = "beta" },
    { version = 1, active_ids = {}, extra = true },
    { version = 1, active_ids = {}, current_id = false },
    { version = 1, active_ids = { "bad/id" } },
    { version = 1, active_ids = vim.empty_dict() },
}
for _, invalid in ipairs(invalid_inputs) do
    ok, err = storage.write_resume(invalid)
    assert(not ok and type(err) == "string", vim.inspect(invalid))
    fixture.equal(original, vim.fn.readfile(resume_path))
end
-- A current session may be absent while other sessions remain active.
assert(storage.write_resume({ version = 1, active_ids = { "alpha" } }))

-- Only successful lifecycle commits authorize publication. Observe this through
-- the public exit API and persisted selection, not internal management flags.
fixture.setup()
local api = require("sess.api")
original = vim.fn.readfile(resume_path)
assert(api.resume.exit())
fixture.equal(original, vim.fn.readfile(resume_path))
ok, err = api.session.create(fixture.directory("rejected"), {
    hooks = {
        before_transition = function()
            error("reject create")
        end,
    },
})
assert(not ok and err:match("reject create"), tostring(err))
assert(api.resume.exit())
fixture.equal(original, vim.fn.readfile(resume_path))
local a, b
ok, err, a = api.session.create(fixture.directory("a"))
assert(ok, err)
ok, err, b = api.session.create(fixture.directory("b"))
assert(ok, err)
assert(api.resume.exit())
ok, err, record = storage.read_resume()
assert(ok, err)
fixture.equal({ version = 1, active_ids = { a.id, b.id }, current_id = b.id }, record)
assert(api.session.unload(b))
assert(api.resume.exit())
ok, err, record = storage.read_resume()
assert(ok, err)
fixture.equal({ version = 1, active_ids = { a.id } }, record)
assert(api.session.unload(a))
assert(api.resume.exit())
ok, err, record = storage.read_resume()
assert(ok, err)
fixture.equal({ version = 1, active_ids = {} }, record)

-- resume_recovery.lua verifies recorded ordering and current-first selection
-- through genuine startup and api.state.active(), including partial recovery.

-- Filesystem fault injection proves failed publication retains the old bytes.
assert(storage.write_resume(previous))
original = vim.fn.readfile(resume_path)
local replacement = { version = 1, active_ids = { "new_selection" }, current_id = "new_selection" }
for _, operation in ipairs({ "fs_mkstemp", "fs_fsync", "fs_rename" }) do
    local original_operation = vim.uv[operation]
    vim.uv[operation] = function()
        return nil, "injected " .. operation .. " failure"
    end
    ok, err = storage.write_resume(replacement)
    vim.uv[operation] = original_operation
    assert(not ok and err:match("injected " .. operation .. " failure"), tostring(err))
    fixture.equal(original, vim.fn.readfile(resume_path))
end
local write = vim.uv.fs_write
local partial_written = false
vim.uv.fs_write = function(fd, content, offset)
    if not partial_written then
        partial_written = true
        return write(fd, content:sub(1, 7), offset)
    end
    return nil, "injected partial write failure"
end
ok, err = storage.write_resume(replacement)
vim.uv.fs_write = write
assert(not ok and err:match("injected partial write failure"), tostring(err))
fixture.equal(original, vim.fn.readfile(resume_path))

local mkstemp, close = vim.uv.fs_mkstemp, vim.uv.fs_close
local temporary_fd
vim.uv.fs_mkstemp = function(pattern)
    local fd, path = mkstemp(pattern)
    temporary_fd = fd
    return fd, path
end
vim.uv.fs_close = function(fd)
    if fd == temporary_fd then
        return nil, "injected temporary close failure"
    end
    return close(fd)
end
ok, err = storage.write_resume(replacement)
vim.uv.fs_mkstemp, vim.uv.fs_close = mkstemp, close
assert(not ok and err:match("injected temporary close failure"), tostring(err))
fixture.equal(original, vim.fn.readfile(resume_path))
-- Retry the retained failed-close handle through normal reinitialization.
assert(storage.init(fixture.root .. "/store"))
for _, name in ipairs(vim.fn.readdir(fixture.root .. "/store")) do
    assert(not name:match("%.tmp%-"), "leaked temporary resume record: " .. name)
end

local read = vim.uv.fs_read
vim.uv.fs_read = function()
    return nil, "injected resume read failure"
end
ok, err, record = storage.read_resume()
local write_ok, write_err = storage.write_resume(replacement)
vim.uv.fs_read = read
assert(not ok and err:match("injected resume read failure"), tostring(err))
fixture.equal(nil, record)
assert(not write_ok and write_err:match("injected resume read failure"), tostring(write_err))
fixture.equal(original, vim.fn.readfile(resume_path))

-- Whole-document replacement does not merge another instance's selection.
assert(storage.write_resume(replacement))
ok, err, record = storage.read_resume()
assert(ok, err)
fixture.equal(replacement, record)

-- Both dangling and live symlink leaves are refused, never followed or repaired.
assert(vim.uv.fs_unlink(resume_path))
local outside = fixture.root .. "/outside.json"
for _, present in ipairs({ false, true }) do
    if present then
        vim.fn.writefile({ "outside content" }, outside)
    end
    assert(vim.uv.fs_symlink(outside, resume_path))
    ok, err, record = storage.read_resume()
    assert(not ok and err:match("untrusted resume record path"), tostring(err))
    fixture.equal(nil, record)
    ok, err = storage.write_resume(previous)
    assert(not ok and err:match("untrusted resume record path"), tostring(err))
    fixture.equal("link", vim.uv.fs_lstat(resume_path).type)
    if present then
        fixture.equal({ "outside content" }, vim.fn.readfile(outside))
    end
    assert(vim.uv.fs_unlink(resume_path))
end

-- Platforms without descriptor namespaces retain bounded path validation and
-- atomic replacement, matching the existing storage platform fallback.
local uname = vim.uv.os_uname
vim.uv.os_uname = function()
    return { sysname = "resume-test-fallback" }
end
ok, err = storage.init(fixture.root .. "/fallback-store")
vim.uv.os_uname = uname
assert(ok, err)
assert(storage.write_resume(previous))
local rename = vim.uv.fs_rename
vim.uv.fs_rename = function()
    return nil, "injected fallback rename failure"
end
ok, err = storage.write_resume(replacement)
vim.uv.fs_rename = rename
assert(not ok and err:match("injected fallback rename failure"), tostring(err))
ok, err, record = storage.read_resume()
assert(ok, err)
fixture.equal(previous, record)
