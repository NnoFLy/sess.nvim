-- FreeBSD must use O_DIRECTORY|O_NOFOLLOW, not O_DIRECT|O_CREAT.
-- Mock capability discovery on other hosts; all filesystem operations remain real.
local original_uname = vim.uv.os_uname
local original_open = vim.uv.fs_open
local freebsd_root = fixture.root .. "/freebsd-store"
local root_flags
local actual_sysname = original_uname().sysname

vim.uv.os_uname = function()
    return { sysname = "FreeBSD" }
end
vim.uv.fs_open = function(path, flags, mode)
    if path == freebsd_root then
        root_flags = flags
    end
    return original_open(path, flags, mode)
end
fixture.setup("freebsd-store")
vim.uv.fs_open = original_open
vim.uv.os_uname = original_uname

assert(root_flags == 131072 + 256, "FreeBSD descriptor flags lost no-follow capability")

-- On the actual platform, exercise the no-follow read path too. Linux cannot
-- interpret FreeBSD's distinct O_NOFOLLOW value when only capability discovery
-- is mocked.
if actual_sysname == "FreeBSD" then
    local storage = require("sess.storage")
    local api = require("sess.api")
    local ok, err, item = api.session.create(fixture.directory("project"))
    assert(ok, tostring(err))
    local metadata = assert(storage.get_session_path(item.id)):gsub("session%.vim$", "metadata.json")
    local outside = fixture.directory("outside") .. "/metadata.json"
    vim.fn.writefile({ vim.json.encode(item.metadata) }, outside)
    assert(vim.uv.fs_unlink(metadata))
    assert(vim.uv.fs_symlink(outside, metadata))
    local rejected, rejected_err = storage.read_metadata(item.id)
    assert(not rejected and tostring(rejected_err):match("ELOOP"), "FreeBSD read followed a metadata symlink")
end
