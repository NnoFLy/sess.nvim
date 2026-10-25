-- Disposable stable-Neovim primitive check, not plugin storage code.
local uv = vim.uv
local root = assert(vim.env.SESS_DURABLE_ROOT)
local function checked(value, err)
    assert(value ~= nil and value ~= false, tostring(err))
    return value
end
local function sync_directory(path)
    local fd = checked(uv.fs_open(path, "r", 0))
    checked(uv.fs_fsync(fd))
    checked(uv.fs_close(fd))
end
sync_directory(vim.fs.dirname(root))
local owner = root .. "/lua-owner"
checked(uv.fs_mkdir(owner, 448))
sync_directory(root)
local fd = checked(uv.fs_open(owner .. "/record.tmp", "wx", 384))
assert(checked(uv.fs_write(fd, '{"synthetic":true}\n', 0)) == 19)
checked(uv.fs_fsync(fd))
checked(uv.fs_close(fd))
checked(uv.fs_rename(owner .. "/record.tmp", owner .. "/record.json"))
sync_directory(owner)
local trash = root .. "/lua-trash"
checked(uv.fs_mkdir(trash, 448))
sync_directory(root)
checked(uv.fs_rename(owner, trash .. "/owner"))
sync_directory(root)
sync_directory(trash)
checked(uv.fs_unlink(trash .. "/owner/record.json"))
sync_directory(trash .. "/owner")
checked(uv.fs_rmdir(trash .. "/owner"))
sync_directory(trash)
local failed, error_message = uv.fs_fsync(-1)
assert(not failed and error_message:match("EBADF"))
print("NVIM=" .. tostring(vim.version()))
print("LIBUV=" .. uv.version_string())
print("FILE_DIRECTORY_FSYNC_RENAME_TRASH=pass")
print("INVALID_FD_FSYNC=EBADF")
print("UV_FS_FLOCK=" .. type(uv.fs_flock))
print("UV_FS_FCNTL=" .. type(uv.fs_fcntl))
-- LuaJIT FFI is an investigated binding, not a selected plugin architecture.
local ffi = require("ffi")
ffi.cdef("int flock(int fd, int operation);")
local lock_path = root .. "/lua-lock"
local first = checked(uv.fs_open(lock_path, "w", 384))
local second = checked(uv.fs_open(lock_path, "r+", 384))
assert(ffi.C.flock(first, 6) == 0) -- Linux LOCK_EX | LOCK_NB
assert(ffi.C.flock(second, 6) == -1)
assert(ffi.errno() == 11) -- Linux EAGAIN/EWOULDBLOCK on this pinned tuple
checked(uv.fs_close(first))
assert(ffi.C.flock(second, 6) == 0)
checked(uv.fs_close(second))
print("LUAJIT_FFI_FLOCK_CONFLICT_CLOSE_RELEASE=pass")
