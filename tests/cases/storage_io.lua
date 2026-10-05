fixture.setup()

local storage = require("sess.storage")
local api = require("sess.api")

local ok, err, item = api.session.create(fixture.directory("project"))
assert(ok, err)

local directory = fixture.root .. "/store/sessions/" .. item.id
local metadata_path = directory .. "/metadata.json"
local original = vim.fn.readfile(metadata_path)
local updated = vim.deepcopy(item.metadata)
updated.name = "must not be committed"

-- A close failure must not publish the temporary metadata file, even when
-- descriptor writes and fsync succeeded.
local close = vim.uv.fs_close
vim.uv.fs_close = function()
    return false, "injected close failure"
end

ok, err = storage.write_metadata(item.id, updated)
vim.uv.fs_close = close
assert(not ok and err:match("injected close failure"), tostring(err))
fixture.equal(original, vim.fn.readfile(metadata_path))

-- A write failure remains primary while temporary and parent close failures
-- are retained as cleanup diagnostics.
local close_calls = 0
vim.uv.fs_close = function(fd)
    close_calls = close_calls + 1
    if close_calls > 2 then
        return false, "injected cleanup close failure"
    end
    return close(fd)
end
local write = vim.uv.fs_write
vim.uv.fs_write = function()
    return nil, "injected write failure"
end
ok, err = storage.write_metadata(item.id, updated)
vim.uv.fs_write = write
vim.uv.fs_close = close
assert(not ok and err:match("injected write failure"), tostring(err))
assert(err:match("injected cleanup close failure"), tostring(err))

for _, name in ipairs(vim.fn.readdir(directory)) do
    assert(not name:match("%.tmp%-"), "leaked temporary file: " .. name)
end

-- Preserve the filesystem's read error instead of returning nil without one.
local read = vim.uv.fs_read
vim.uv.fs_read = function()
    return nil, "injected read failure"
end

local metadata
metadata, err = storage.read_metadata(item.id)
vim.uv.fs_read = read
fixture.equal(nil, metadata)
fixture.equal("injected read failure", err)

-- EOF before the validated size is a failed read, not partial success.
vim.uv.fs_read = function()
    return ""
end
metadata, err = storage.read_metadata(item.id)
vim.uv.fs_read = read
fixture.equal(nil, metadata)
assert(err:match("short read"), tostring(err))

local mkstemp = vim.uv.fs_mkstemp
local temporary_pattern
vim.uv.fs_mkstemp = function(pattern)
    temporary_pattern = pattern
    return mkstemp(pattern)
end
assert(storage.write_metadata(item.id, updated))
vim.uv.fs_mkstemp = mkstemp
assert(temporary_pattern:match("/fd/%d+/"), "metadata write was not descriptor-anchored")
fixture.equal(updated, storage.read_metadata(item.id))
