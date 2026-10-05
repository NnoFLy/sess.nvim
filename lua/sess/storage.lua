local M = {}

local consts = require("sess.consts")
local mark = require("sess.mark")
local path_utils = require("sess.path")

---@class Sess.SessionFiles
---@field metadata string
---@field session string

---@class Sess.SessionPaths
---@field dir string
---@field metadata string
---@field session string

---@class Sess.TrashEntry
---@field key string Stable trash directory name.
---@field id Sess.SessionId Original session id.
---@field metadata Sess.SessionMetadata
---@field deleted_at Sess.Timestamp

local root_path ---@type string?
local root_fd ---@type integer?
local descriptor_prefix ---@type string?
local directory_open_flags ---@type integer?
local file_open_flags ---@type integer?
local descriptor_mode = false
local pending_descriptors = {} ---@type table<integer, string>
local pending_descriptor_count = 0
local retained_descriptor_count = 0

---@class Sess.DescriptorState
---@field label string?
---@field cleanup_pending boolean
---@field counts_toward_capacity boolean
local descriptor_states = {} ---@type table<integer, Sess.DescriptorState>
local active_descriptor_count = 0

-- A failed close keeps ownership of the descriptor here. Do not allow cleanup
-- failures to turn into an unbounded descriptor leak: once this small queue is
-- full, new descriptor-producing operations fail before opening another one.
-- Handles which race queue saturation remain in descriptor_states until the
-- owning retry pass succeeds; descriptor-producing operations are refused
-- while the retained collection is at its bound.
local MAX_PENDING_DESCRIPTORS = 8
local CLOSE_ATTEMPTS = 3

local O_RDONLY = (vim.uv.constants and vim.uv.constants.O_RDONLY) or 0

local function append_error(primary, cleanup)
    if not cleanup then
        return primary
    end
    if not primary or primary == "" then
        return cleanup
    end
    if tostring(primary):find(tostring(cleanup), 1, true) then
        return primary
    end
    return tostring(primary) .. "; " .. tostring(cleanup)
end

local function pending_close_error(fd, label)
    local state = descriptor_states[fd]
    local descriptor_label = label
        or (state and state.label)
        or pending_descriptors[fd]
        or "descriptor"
    return "failed to close " .. descriptor_label .. ": close is still pending"
end

local function track_descriptor(fd, label, counts_toward_capacity)
    if not fd then
        return
    end
    descriptor_states[fd] = {
        label = label,
        cleanup_pending = false,
        counts_toward_capacity = counts_toward_capacity ~= false,
    }
    if descriptor_states[fd].counts_toward_capacity then
        active_descriptor_count = active_descriptor_count + 1
    end
end

local function forget_descriptor(fd)
    local state = descriptor_states[fd]
    if not state then
        return
    end
    if state.counts_toward_capacity and not state.cleanup_pending then
        active_descriptor_count = active_descriptor_count - 1
    end
    if state.cleanup_pending then
        retained_descriptor_count = retained_descriptor_count - 1
    end
    if pending_descriptors[fd] then
        pending_descriptors[fd] = nil
        pending_descriptor_count = pending_descriptor_count - 1
    end
    descriptor_states[fd] = nil
end

local function close_descriptor(fd, label, retry_pending)
    if not fd then
        return true
    end

    local state = descriptor_states[fd]
    -- A caller which does not own a retained handle must never issue a second
    -- close for it. The retry path below is the sole owner of retries.
    if state and state.cleanup_pending and not retry_pending then
        return false, pending_close_error(fd, label)
    end

    local close_err
    for _ = 1, CLOSE_ATTEMPTS do
        local closed
        closed, close_err = vim.uv.fs_close(fd)
        if closed then
            forget_descriptor(fd)
            return true
        end
    end

    -- Keep the descriptor reachable until a later retry succeeds. Normally an
    -- active descriptor has already reserved a slot in the bounded pending
    -- collection. The saturation branch handles a persistent descriptor (or a
    -- close race) that reaches this point while that collection is full.
    if not state then
        state = {
            label = label,
            cleanup_pending = false,
            counts_toward_capacity = true,
        }
        descriptor_states[fd] = state
        active_descriptor_count = active_descriptor_count + 1
    end
    state.label = state.label or label
    if not state.cleanup_pending then
        state.cleanup_pending = true
        if state.counts_toward_capacity then
            active_descriptor_count = active_descriptor_count - 1
        end
        retained_descriptor_count = retained_descriptor_count + 1
        if pending_descriptor_count < MAX_PENDING_DESCRIPTORS then
            pending_descriptors[fd] = state.label
            pending_descriptor_count = pending_descriptor_count + 1
        end
    end

    local description =
        "failed to close " .. (label or state.label or "descriptor") .. ": " .. tostring(close_err or "unknown error")
    if not pending_descriptors[fd] then
        description = description
            .. "; descriptor cleanup queue is full ("
            .. MAX_PENDING_DESCRIPTORS
            .. " pending descriptors); descriptor retained for retry"
    end
    return false, description
end

local function descriptor_capacity_full(path, action)
    if retained_descriptor_count + active_descriptor_count < MAX_PENDING_DESCRIPTORS then
        return false
    end
    return true,
        "descriptor cleanup queue is full ("
            .. MAX_PENDING_DESCRIPTORS
            .. " retained descriptors); refusing to "
            .. action
            .. " "
            .. tostring(path)
end

local function open_descriptor(path, flags, mode, counts_toward_capacity)
    local full, capacity_err = descriptor_capacity_full(path, "open")
    if full then
        return nil, capacity_err
    end
    local fd, open_err = vim.uv.fs_open(path, flags, mode)
    if fd then
        track_descriptor(fd, nil, counts_toward_capacity)
    end
    return fd, open_err
end

local function make_temporary(path)
    local full, capacity_err = descriptor_capacity_full(path, "create temporary file")
    if full then
        return nil, capacity_err
    end
    local fd, temporary = vim.uv.fs_mkstemp(path)
    if fd then
        track_descriptor(fd, "temporary file", true)
    end
    return fd, temporary
end

-- libuv does not expose O_DIRECTORY/O_NOFOLLOW. These are the values from
-- the platform fcntl headers, kept named so the capability boundary is
-- explicit instead of mixing unrelated open flags at each call site.
local DESCRIPTOR_FLAGS = {
    Linux = {
        directory = 65536 + 131072, -- O_DIRECTORY | O_NOFOLLOW
        no_follow = 131072, -- O_NOFOLLOW
    },
    Darwin = {
        directory = 1048576 + 256, -- O_DIRECTORY | O_NOFOLLOW
        no_follow = 256, -- O_NOFOLLOW
    },
    FreeBSD = {
        -- sys/fcntl.h: O_DIRECTORY=0x00020000, O_NOFOLLOW=0x00000100.
        directory = 131072 + 256,
        no_follow = 256,
    },
}

local SESSIONS_DIR = "sessions"
local TRASH_DIR = "trash"

local METADATA_FILE = "metadata.json"
local SESSION_FILE = "session.vim"

-- Compatibility export; mark syntax itself is domain-owned by sess.mark.
M.validate_mark = mark.validate

-- Internal helpers
local validate_id
local trusted_fallback_path

---@param ...string
---@return string
local function join(...)
    return vim.fs.joinpath(...)
end

local function assert_initialized()
    if not root_path then
        error("sess.storage is not initialized")
    end
end

---@return string
local function sessions_path()
    assert_initialized()

    return join(root_path, SESSIONS_DIR)
end

---@return string
local function trash_path()
    assert_initialized()

    return join(root_path, TRASH_DIR)
end

---@param id Sess.SessionId
---@return Sess.SessionPaths
local function session_paths(id)
    assert_initialized()

    local valid, err = validate_id(id)
    if not valid then
        error(err)
    end

    local dir = join(sessions_path(), id)

    return {
        dir = dir,
        metadata = join(dir, METADATA_FILE),
        session = join(dir, SESSION_FILE),
    }
end

---@param path string
---@return boolean
local function file_exists(path)
    local stat = vim.uv.fs_lstat(path)
    return stat ~= nil and stat.type == "file"
end

local function trusted_dir(path, label)
    local stat, err = vim.uv.fs_lstat(path)
    if not stat then
        return false, "failed to access " .. label .. ": " .. tostring(err or path)
    end
    if stat.type ~= "directory" then
        return false, "untrusted " .. label .. " (expected a directory): " .. path
    end
    return true
end

---@param path string
---@return boolean
local function dir_exists(path)
    local stat = vim.uv.fs_lstat(path)

    return stat ~= nil and stat.type == "directory"
end

local function trash_entry_path(key)
    if type(key) ~= "string" or key == "" or not key:match("^[%w_.%-]+$") then
        return nil, "invalid trash entry key"
    end

    return join(trash_path(), key)
end

local function ensure_private_dir(path, label)
    -- Validate the complete configured path before mkdir -p. Checking only the
    -- leaf would allow a symlinked configured-root ancestor to redirect the
    -- store outside the user's selected path.
    local trusted, trust_err = trusted_fallback_path(path, label)
    if not trusted then
        return false, trust_err
    end

    local existing = vim.uv.fs_lstat(path)
    if existing then
        if existing.type ~= "directory" then
            return false, "untrusted " .. label .. " (expected a directory): " .. path
        end
    elseif vim.fn.mkdir(path, "p") ~= 1 then
        return false, "failed to create " .. label .. ": " .. path
    end

    trusted, trust_err = trusted_dir(path, label)
    if not trusted then
        return false, trust_err
    end

    local ok, err = vim.uv.fs_chmod(path, 448) -- 0700
    if not ok then
        return false, "failed to restrict " .. label .. ": " .. tostring(err)
    end

    return true
end

---@param path string
---@return string?, string?
local function same_file(left, right)
    return left
        and right
        and left.type == "file"
        and right.type == "file"
        and left.dev == right.dev
        and left.ino == right.ino
end

local function unlink_with_error(path, previous)
    local removed, remove_err = vim.uv.fs_unlink(path)
    if not removed then
        return tostring(previous or "operation failed") .. "; failed to remove temporary file: " .. tostring(remove_err)
    end
    return previous
end

local function write_all(fd, content)
    local offset = 0
    while offset < #content do
        local written, write_err = vim.uv.fs_write(fd, content:sub(offset + 1), -1)
        if not written or written == 0 then
            return false, write_err or "failed to write file"
        end
        offset = offset + written
    end
    return true
end

local function read_all(fd, size)
    local chunks = {}
    local offset = 0
    while offset < size do
        local chunk, read_err = vim.uv.fs_read(fd, size - offset, offset)
        if not chunk then
            return nil, read_err
        end
        if #chunk == 0 then
            return nil, string.format("short read: expected %d bytes, got %d", size, offset)
        end
        chunks[#chunks + 1] = chunk
        offset = offset + #chunk
    end
    return table.concat(chunks)
end

local function storage_relative(path)
    if not root_path or path == root_path then
        return ""
    end
    local prefix = root_path .. "/"
    if path:sub(1, #prefix) ~= prefix then
        return nil
    end
    local relative = path:sub(#prefix + 1)
    if relative == "" or relative:match("(^|/)%.%.?(/|$)") then
        return nil
    end
    return relative
end

local function descriptor_path(fd, child)
    if not descriptor_prefix then
        return nil
    end
    return descriptor_prefix .. "/" .. tostring(fd) .. (child and "/" .. child or "")
end

trusted_fallback_path = function(path, label)
    local relative = storage_relative(path)
    if relative == nil then
        return false, "untrusted " .. label .. " path: " .. tostring(path)
    end

    -- Walk upward through every existing component, including the ancestors
    -- above root_path. Missing components are safe to create later; their
    -- existing parents are still checked. vim.fs.dirname handles POSIX roots,
    -- drive roots, and UNC roots without assuming a separator layout here.
    local current = path
    while true do
        local stat, stat_err = vim.uv.fs_lstat(current)
        if stat then
            if stat.type ~= "directory" then
                return false, "untrusted " .. label .. " path: " .. tostring(current)
            end
        elseif stat_err and not tostring(stat_err):match("ENOENT") then
            return false, "failed to access " .. label .. ": " .. tostring(stat_err)
        end

        local parent = vim.fs.dirname(current)
        if parent == current then
            break
        end
        current = parent
    end
    return true
end

local function open_storage_dir(path)
    if not descriptor_mode then
        local trusted, trust_err = trusted_fallback_path(path, "storage parent directory")
        if not trusted then
            return nil, trust_err
        end
        trusted, trust_err = trusted_dir(path, "storage parent directory")
        if not trusted then
            return nil, trust_err
        end
        return path
    end

    local relative = storage_relative(path)
    if relative == nil or not root_fd or not directory_open_flags then
        return nil, "secure no-follow storage descriptors are unavailable for " .. tostring(path)
    end

    -- Walk each component from the already-opened root. Opening only the
    -- final pathname component would still allow an attacker to replace an
    -- intermediate directory with a symlink between checks.
    local current, err = open_descriptor(descriptor_path(root_fd), "r", 0)
    if not current then
        return nil, err
    end
    for component in relative:gmatch("[^/]+") do
        local child, child_err = open_descriptor(descriptor_path(current, component), directory_open_flags, 0)
        local current_closed, current_close_err = close_descriptor(current, "storage directory")
        if current_closed then
            current = nil
        end
        if not child then
            return nil, append_error(child_err, current_closed and nil or current_close_err)
        end
        if not current_closed then
            local child_closed, child_close_err = close_descriptor(child, "storage directory")
            return nil, append_error(current_close_err, child_closed and nil or child_close_err)
        end
        current = child
    end

    local stat = vim.uv.fs_fstat(current)
    if not stat or stat.type ~= "directory" then
        local closed, close_err = close_descriptor(current, "storage parent directory")
        if closed then
            current = nil
        end
        return nil, append_error("untrusted storage parent directory: " .. path, closed and nil or close_err)
    end
    return current
end

local function read_file(path)
    local fd
    local parent_fd
    local expected
    local open_err
    if descriptor_mode then
        if not file_open_flags then
            return nil, "secure no-follow file descriptors are unavailable for " .. path
        end

        local parent, parent_err = open_storage_dir(vim.fs.dirname(path))
        if not parent then
            return nil, parent_err
        end
        parent_fd = parent

        -- The parent descriptor is stable and the no-follow flag rejects a
        -- replaced leaf. Do not lstat and then reopen the attacker-controlled
        -- pathname from the storage root.
        fd, open_err = open_descriptor(
            descriptor_path(parent_fd, vim.fs.basename(path)),
            file_open_flags,
            0
        )
        local parent_closed, parent_close_err = close_descriptor(parent_fd, "storage parent")
        if parent_closed then
            parent_fd = nil
        end
        if not fd then
            return nil, append_error(open_err, parent_closed and nil or parent_close_err)
        end
        if not parent_closed then
            local fd_closed, fd_close_err = close_descriptor(fd, "file")
            if fd_closed then
                fd = nil
            end
            return nil, append_error(parent_close_err, fd_closed and nil or fd_close_err)
        end
    else
        local parent = vim.fs.dirname(path)
        local trusted, trust_err = trusted_fallback_path(parent, "storage parent directory")
        if not trusted then
            return nil, trust_err
        end
        trusted, trust_err = trusted_dir(parent, "storage parent directory")
        if not trusted then
            return nil, trust_err
        end

        expected, open_err = vim.uv.fs_lstat(path)
        if not expected then
            return nil, open_err
        end
        if expected.type ~= "file" then
            return nil, "untrusted file path: " .. path
        end

        fd, open_err = open_descriptor(path, "r", 0)
        if not fd then
            return nil, open_err
        end
    end

    local actual = vim.uv.fs_fstat(fd)
    if not actual or actual.type ~= "file" or (expected and not same_file(expected, actual)) then
        local closed, close_err = close_descriptor(fd, "file")
        if closed then
            fd = nil
        end
        return nil,
            append_error(
                "file changed while opening: " .. path,
                closed and nil or close_err
            )
    end

    local content, read_err = read_all(fd, actual.size)
    local closed, close_err = close_descriptor(fd, "file")
    if closed then
        fd = nil
    end
    if not content then
        local message = read_err or "failed to read file"
        return nil, append_error(message, closed and nil or close_err)
    end
    if not closed then
        return nil, close_err
    end

    return content
end

---@param path string
---@param content string
---@return boolean, string?
local function write_file_atomic_path(path, content)
    local parent_path = vim.fs.dirname(path)
    local trusted, trust_err = trusted_fallback_path(parent_path, "storage parent directory")
    if not trusted then
        return false, trust_err
    end
    trusted, trust_err = trusted_dir(parent_path, "storage parent directory")
    if not trusted then
        return false, trust_err
    end

    local fd, temporary = make_temporary(path .. ".tmp-XXXXXX")
    if not fd then
        return false, temporary
    end

    local written, write_err = write_all(fd, content)
    if not written then
        local closed, close_err = close_descriptor(fd, "temporary file")
        if closed then
            fd = nil
        end
        local err = unlink_with_error(temporary, write_err or "failed to write temporary file")
        return false, append_error(err, closed and nil or close_err)
    end

    local synced, sync_err = vim.uv.fs_fsync(fd)
    local closed, close_err = close_descriptor(fd, "temporary file")
    if closed then
        fd = nil
    end
    if not synced or not closed then
        local err = sync_err or (not synced and "failed to sync temporary file")
        err = append_error(err, closed and nil or close_err)
        return false, unlink_with_error(temporary, err)
    end

    local renamed, rename_err = vim.uv.fs_rename(temporary, path)
    if not renamed then
        return false, unlink_with_error(temporary, rename_err)
    end
    return true
end

---@param path string
---@param content string
---@return boolean, string?
local function write_file_atomic(path, content)
    if not descriptor_mode then
        return write_file_atomic_path(path, content)
    end

    local parent_path = vim.fs.dirname(path)
    local parent_fd, parent_err = open_storage_dir(parent_path)
    if not parent_fd then
        return false, parent_err
    end

    local name = vim.fs.basename(path)
    local anchored_parent = descriptor_path(parent_fd)
    local temporary_pattern = anchored_parent .. "/." .. name .. ".tmp-XXXXXX"
    local fd, tmp_path = make_temporary(temporary_pattern)
    if not fd then
        local parent_closed, parent_close_err = close_descriptor(parent_fd, "storage parent")
        if parent_closed then
            parent_fd = nil
        end
        return false, append_error(tmp_path, parent_closed and nil or parent_close_err)
    end

    local temporary = descriptor_path(parent_fd, vim.fs.basename(tmp_path))
    local destination = descriptor_path(parent_fd, name)
    local written, write_err = write_all(fd, content)
    if not written then
        local closed, close_err = close_descriptor(fd, "temporary file")
        if closed then
            fd = nil
        end
        local err = unlink_with_error(temporary, write_err or "failed to write temporary file")
        err = append_error(err, closed and nil or close_err)
        local parent_closed, parent_close_err = close_descriptor(parent_fd, "storage parent")
        if parent_closed then
            parent_fd = nil
        end
        err = append_error(err, parent_closed and nil or parent_close_err)
        return false, err
    end

    local synced, sync_err = vim.uv.fs_fsync(fd)
    local closed, close_err = close_descriptor(fd, "temporary file")
    if closed then
        fd = nil
    end
    if not synced or not closed then
        local err = sync_err or (not synced and "failed to sync temporary file")
        err = append_error(err, closed and nil or close_err)
        err = unlink_with_error(temporary, err)
        local parent_closed, parent_close_err = close_descriptor(parent_fd, "storage parent")
        if parent_closed then
            parent_fd = nil
        end
        err = append_error(err, parent_closed and nil or parent_close_err)
        return false, err
    end

    local rename_ok, rename_err = vim.uv.fs_rename(temporary, destination)
    local err
    if not rename_ok then
        err = unlink_with_error(temporary, rename_err)
    end
    local parent_closed, parent_close_err = close_descriptor(parent_fd, "storage parent")
    if parent_closed then
        parent_fd = nil
    end
    if not rename_ok then
        return false, append_error(err, parent_closed and nil or parent_close_err)
    end
    if not parent_closed then
        return false, parent_close_err
    end

    return true
end

---@param path string
---@return table?, string?
local function read_json(path)
    local content, err = read_file(path)

    if not content then
        return nil, err
    end

    local ok, data = pcall(vim.json.decode, content)

    if not ok then
        return nil, "invalid JSON: " .. tostring(data)
    end

    if type(data) ~= "table" then
        return nil, "JSON root must be an object"
    end

    return data
end

---@param data table
---@return Sess.SessionMetadata?, string?
local function validate_metadata(data)
    if type(data) ~= "table" then
        return nil, "invalid session metadata: expected an object"
    end

    local fields = {
        version = "number",
        name = "string",
        cwd = "string",
        created_at = "number",
        last_used_at = "number",
        pinned = "boolean",
    }

    for field, expected_type in pairs(fields) do
        if type(data[field]) ~= expected_type then
            return nil,
                string.format("invalid session metadata: field %s must be %s", field, expected_type)
        end
    end

    if data.version ~= consts.get_version() then
        return nil, "unsupported session metadata version: " .. tostring(data.version)
    end

    if vim.trim(data.name) == "" then
        return nil, "invalid session metadata: field name cannot be empty"
    end

    if vim.trim(data.cwd) == "" then
        return nil, "invalid session metadata: field cwd must be a non-empty path"
    end

    local canonical_cwd = path_utils.canonical_absolute(data.cwd)
    if not canonical_cwd or canonical_cwd ~= data.cwd then
        return nil, "invalid session metadata: field cwd must be an absolute canonical path"
    end

    local timestamps = { data.created_at, data.last_used_at }
    for _, timestamp in ipairs(timestamps) do
        if
            timestamp ~= timestamp
            or timestamp < 0
            or timestamp >= math.huge
            or timestamp ~= math.floor(timestamp)
        then
            return nil, "invalid session metadata: timestamps must be non-negative integers"
        end
    end

    return data --[[@as Sess.SessionMetadata]]
end

---@param path string
---@param data table
---@return boolean, string?
local function write_json(path, data)
    local ok, content = pcall(vim.json.encode, data)

    if not ok then
        return false, "failed to encode JSON: " .. tostring(content)
    end

    return write_file_atomic(path, content)
end

---@param id Sess.SessionId
---@return boolean, string?
validate_id = function(id)
    if type(id) ~= "string" then
        return false, "session id must be a string"
    end

    if id == "" then
        return false, "session id cannot be empty"
    end

    -- Session ids become directory names; keep them deliberately portable.
    if not id:match("^[%w_-]+$") then
        return false, "invalid session id: " .. id
    end

    return true
end

---@param id Sess.SessionId
---@param generate fun(path: string, fd: integer?)
---@return boolean, string?
local function replace_snapshot_path(id, generate)
    local paths = session_paths(id)
    local trusted, trust_err = trusted_fallback_path(paths.dir, "session directory")
    if not trusted then
        return false, trust_err
    end
    trusted, trust_err = trusted_dir(paths.dir, "session directory")
    if not trusted then
        return false, trust_err
    end

    local fd, temporary = make_temporary(paths.session .. ".tmp-XXXXXX")
    if not fd then
        return false, temporary
    end

    local called, generated, generate_err = pcall(generate, temporary, nil)
    if not called or generated == false then
        local closed, close_err = close_descriptor(fd, "temporary snapshot")
        if closed then
            fd = nil
        end
        local err = unlink_with_error(temporary, tostring(called and generate_err or generated))
        return false, append_error(err, closed and nil or close_err)
    end

    local temporary_stat = vim.uv.fs_lstat(temporary)
    if not temporary_stat or temporary_stat.type ~= "file" then
        local closed, close_err = close_descriptor(fd, "temporary snapshot")
        if closed then
            fd = nil
        end
        local err = unlink_with_error(temporary, "snapshot generator did not create a regular file")
        return false, append_error(err, closed and nil or close_err)
    end

    local synced, sync_err = vim.uv.fs_fsync(fd)
    local closed, close_err = close_descriptor(fd, "temporary snapshot")
    if closed then
        fd = nil
    end
    if not synced or not closed then
        local err = sync_err or (not synced and "failed to sync temporary snapshot")
        err = append_error(err, closed and nil or close_err)
        return false, unlink_with_error(temporary, err)
    end

    local renamed, rename_err = vim.uv.fs_rename(temporary, paths.session)
    if not renamed then
        return false, unlink_with_error(temporary, rename_err)
    end
    return true
end

---@param id Sess.SessionId
function M.replace_snapshot(id, generate)
    if not descriptor_mode then
        return replace_snapshot_path(id, generate)
    end

    local trusted, trust_err = trusted_dir(sessions_path(), "sessions directory")
    if not trusted then
        return false, trust_err
    end

    local paths = session_paths(id)
    local parent_fd, parent_err = open_storage_dir(paths.dir)
    if not parent_fd then
        return false, parent_err
    end

    local name = vim.fs.basename(paths.session)
    local temporary_pattern = descriptor_path(parent_fd) .. "/." .. name .. ".tmp-XXXXXX"
    local fd, temporary = make_temporary(temporary_pattern)    if not fd then
        local parent_closed, parent_close_err = close_descriptor(parent_fd, "session directory")
        if parent_closed then
            parent_fd = nil
        end
        return false, append_error(temporary, parent_closed and nil or parent_close_err)
    end

    local temporary_name = vim.fs.basename(temporary)
    temporary = descriptor_path(parent_fd, temporary_name)
    local destination = descriptor_path(parent_fd, name)

    -- Keep both descriptors open while the editor generates the snapshot. The
    -- editor receives an already-created descriptor path, and replacement is
    -- anchored to the opened session directory rather than its pathname.
    local called, generated, generate_err = pcall(generate, temporary, fd)
    if not called or generated == false then
        local generation_err = unlink_with_error(temporary, tostring(called and generate_err or generated))
        local closed, close_err = close_descriptor(fd, "temporary snapshot")
        if closed then
            fd = nil
        end
        generation_err = append_error(generation_err, closed and nil or close_err)
        local parent_closed, parent_close_err = close_descriptor(parent_fd, "session directory")
        if parent_closed then
            parent_fd = nil
        end
        generation_err = append_error(generation_err, parent_closed and nil or parent_close_err)
        return false, generation_err
    end

    local temporary_stat = vim.uv.fs_fstat(fd)
    local path_stat = vim.uv.fs_lstat(temporary)
    if
        not temporary_stat
        or temporary_stat.type ~= "file"
        or not same_file(temporary_stat, path_stat)
    then
        local validation_err = unlink_with_error(temporary, "snapshot temporary file was replaced while generating")
        local closed, close_err = close_descriptor(fd, "temporary snapshot")
        if closed then
            fd = nil
        end
        validation_err = append_error(validation_err, closed and nil or close_err)
        local parent_closed, parent_close_err = close_descriptor(parent_fd, "session directory")
        if parent_closed then
            parent_fd = nil
        end
        validation_err = append_error(validation_err, parent_closed and nil or parent_close_err)
        return false, validation_err
    end

    local synced, sync_err = vim.uv.fs_fsync(fd)
    local closed, close_err = close_descriptor(fd, "temporary snapshot")
    if closed then
        fd = nil
    end
    if not synced or not closed then
        local snapshot_err = sync_err or (not synced and "failed to sync temporary snapshot")
        snapshot_err = append_error(snapshot_err, closed and nil or close_err)
        snapshot_err = unlink_with_error(temporary, snapshot_err)
        local parent_closed, parent_close_err = close_descriptor(parent_fd, "session directory")
        if parent_closed then
            parent_fd = nil
        end
        snapshot_err = append_error(snapshot_err, parent_closed and nil or parent_close_err)
        return false, snapshot_err
    end

    local renamed, rename_err = vim.uv.fs_rename(temporary, destination)
    local snapshot_err
    if not renamed then
        snapshot_err = unlink_with_error(temporary, rename_err)
    end
    local parent_closed, parent_close_err = close_descriptor(parent_fd, "session directory")
    if parent_closed then
        parent_fd = nil
    end
    if not renamed then
        return false, append_error(snapshot_err, parent_closed and nil or parent_close_err)
    end
    if not parent_closed then
        return false, parent_close_err
    end

    return true
end

-- Initialization

local function close_root_descriptor()
    if root_fd then
        -- The root may be retained in either the pending queue or the bounded
        -- retained-handle collection. This owner is allowed to retry both states;
        -- ordinary callers still cannot issue a second close themselves.
        local closed, close_err = close_descriptor(root_fd, "storage directory", true)
        if not closed then
            return false, close_err
        end
        root_fd = nil
    end
    descriptor_prefix = nil
    directory_open_flags, file_open_flags = nil, nil
    descriptor_mode = false
    return true
end

local function retry_retained_descriptors()
    local errors = {}
    for fd, state in pairs(descriptor_states) do
        if state.cleanup_pending then
            local closed, close_err = close_descriptor(fd, state.label, true)
            if not closed then
                errors[#errors + 1] = close_err
            end
        end
    end
    if #errors > 0 then
        return false, table.concat(errors, "; ")
    end
    return true
end

local function establish_root_descriptor()
    local capabilities = DESCRIPTOR_FLAGS[vim.uv.os_uname().sysname]
    if not capabilities then
        directory_open_flags, file_open_flags = nil, nil
        -- Some libuv targets do not expose portable O_DIRECTORY/O_NOFOLLOW
        -- values. Keep initialization usable there, but route persistence
        -- through the bounded path fallback and document its race limitation.
        descriptor_mode = false
        return true
    end

    directory_open_flags = capabilities.directory
    file_open_flags = O_RDONLY + capabilities.no_follow
    -- The root descriptor is persistent rather than an operation-local handle;
    -- it still gets tracked so a failed close remains retryable, but it does
    -- not consume the transient descriptor capacity while the store is live.
    local fd, err = open_descriptor(root_path, directory_open_flags, 0, false)
    if not fd then
        return false, "failed to open storage descriptor: " .. tostring(err)
    end

    for _, prefix in ipairs({ "/proc/self/fd", "/dev/fd" }) do
        local candidate = prefix .. "/" .. tostring(fd)
        local stat = vim.uv.fs_stat(candidate)
        if stat and stat.type == "directory" then
            root_fd = fd
            descriptor_prefix = prefix
            descriptor_mode = true
            return true
        end
    end

    local closed, close_err = close_descriptor(fd, "storage directory")
    -- A descriptor namespace is not guaranteed even on a POSIX target (for
    -- example in a restricted container). Use the same bounded fallback as
    -- other platforms instead of making normal initialization unusable.
    if not closed then
        -- Keep ownership visible to close_root_descriptor so a later init can
        -- retry this failed close instead of losing the handle.
        root_fd = fd
        descriptor_mode = false
        return false, close_err
    end
    descriptor_mode = false
    return true
end

---@param path string
---@return boolean, string?
function M.init(path)
    if type(path) ~= "string" or vim.trim(path) == "" then
        return false, "storage path must be a non-empty string"
    end

    if root_fd then
        local closed, close_err = close_root_descriptor()
        if not closed then
            return false, close_err
        end
    end
    local closed, close_err = retry_retained_descriptors()
    if not closed then
        return false, close_err
    end
    descriptor_mode = false
    root_path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))

    local ok, err = ensure_private_dir(root_path, "storage directory")
    if not ok then
        return false, err
    end

    ok, err = establish_root_descriptor()
    if not ok then
        return false, err
    end

    ok, err = ensure_private_dir(sessions_path(), "sessions directory")
    if not ok then
        local closed, close_err = close_root_descriptor()
        return false, append_error(err, closed and nil or close_err)
    end

    ok, err = ensure_private_dir(trash_path(), "trash directory")
    if not ok then
        local closed, close_err = close_root_descriptor()
        return false, append_error(err, closed and nil or close_err)
    end

    return true
end

function M.root()
    return root_path
end

-- Marks are a separate registry: reassignment never rewrites session records.

local function validate_marks(data)
    if type(data) ~= "table" or data.version ~= 1 then
        return nil, "unsupported mark registry version"
    end
    if type(data.marks) ~= "table" then
        return nil, "mark registry must contain a marks object"
    end
    for mark_value, id in pairs(data.marks) do
        local valid, err = mark.validate(mark_value)
        if not valid then
            return nil, "invalid mark registry: " .. err
        end
        valid, err = validate_id(id)
        if not valid then
            return nil, "invalid mark registry: " .. err
        end
    end
    return data.marks
end

function M.read_marks()
    assert_initialized()
    local trusted, trust_err = trusted_dir(root_path, "storage directory")
    if not trusted then
        return nil, trust_err
    end
    local path = join(root_path, "marks.json")
    local stat, err, code = vim.uv.fs_stat(path)
    if not stat then
        if code == "ENOENT" then
            return {}
        end
        return nil, err
    end
    local data, read_err = read_json(path)
    if not data then
        return nil, read_err
    end
    return validate_marks(data)
end

function M.write_marks(marks)
    assert_initialized()
    local trusted, trust_err = trusted_dir(root_path, "storage directory")
    if not trusted then
        return false, trust_err
    end
    local data = { version = 1, marks = marks }
    local valid, err = validate_marks(data)
    if not valid then
        return false, err
    end
    -- Encode an empty registry as an object, not a JSON array.
    if next(marks) == nil then
        data.marks = vim.empty_dict()
    end
    return write_json(join(root_path, "marks.json"), data)
end

-- Session discovery

---@return Sess.SessionId[], string?
function M.list()
    assert_initialized()

    local trusted, trust_err = trusted_dir(sessions_path(), "sessions directory")
    if not trusted then
        return {}, trust_err
    end

    local ok, entries = pcall(vim.fn.readdir, sessions_path())
    if not ok then
        return {}, tostring(entries)
    end

    ---@type Sess.SessionId[]
    local result = {}

    for _, name in ipairs(entries) do
        local child = join(sessions_path(), name)
        local stat = vim.uv.fs_lstat(child)
        if stat and stat.type == "directory" then
            table.insert(result, name)
        elseif stat and stat.type ~= "file" then
            return {}, "untrusted session path: " .. child
        end
    end

    table.sort(result)

    return result
end

---@param id Sess.SessionId
---@return boolean
function M.exists(id)
    local ok = validate_id(id)

    if not ok then
        return false
    end

    local trusted, trust_err = trusted_dir(sessions_path(), "sessions directory")
    if not trusted then
        return false, trust_err
    end

    local stat, err, code = vim.uv.fs_lstat(session_paths(id).dir)
    if not stat then
        if code == "ENOENT" then
            return false
        end

        return false, err
    end

    if stat.type ~= "directory" then
        return false, "session path is not a directory: " .. id
    end

    return true
end

-- Deleted session discovery and restoration

---@param key string
---@return Sess.SessionId?, Sess.Timestamp?, string?
local function parse_trash_key(key)
    -- The id is deliberately captured greedily so ids containing '-' remain
    -- compatible with the historical <id>-<time>-<counter> layout.
    local id, timestamp = key:match("^(.+)%-(%d+)%-%d+$")
    if not id then
        return nil, nil, "unsupported trash entry name: " .. key
    end

    local valid, err = validate_id(id)
    if not valid then
        return nil, nil, err
    end

    local deleted_at = tonumber(timestamp)
    if not deleted_at or deleted_at < 0 or deleted_at ~= math.floor(deleted_at) then
        return nil, nil, "invalid trash deletion timestamp: " .. timestamp
    end

    -- Reject timestamps that the UI cannot format instead of allowing a
    -- malformed trash directory to crash the deleted-session picker.
    local date_ok, date = pcall(os.date, "*t", deleted_at)
    if not date_ok or type(date) ~= "table" then
        return nil, nil, "invalid trash deletion timestamp: " .. timestamp
    end

    return id, deleted_at, nil
end

---@param key string
---@return Sess.TrashEntry?, string?
local function read_trash_entry(key)
    local path, path_err = trash_entry_path(key)
    if not path then
        return nil, path_err
    end

    local id, deleted_at, parse_err = parse_trash_key(key)
    if not id then
        return nil, parse_err
    end

    local entry_stat = vim.uv.fs_lstat(path)
    if not entry_stat then
        return nil, "trash entry does not exist: " .. key
    end
    if entry_stat.type ~= "directory" then
        return nil, "untrusted trash entry path: " .. key
    end

    local metadata, err = read_json(join(path, METADATA_FILE))
    if not metadata then
        return nil, err
    end

    local valid_metadata, validation_err = validate_metadata(metadata)
    if not valid_metadata then
        return nil, validation_err
    end

    return { key = key, id = id, metadata = valid_metadata, deleted_at = deleted_at }
end

---@return Sess.TrashEntry[], string?, string[]
function M.list_trash()
    assert_initialized()

    local trusted, trust_err = trusted_dir(trash_path(), "trash directory")
    if not trusted then
        return {}, trust_err, {}
    end

    local ok, names = pcall(vim.fn.readdir, trash_path())
    if not ok then
        return {}, tostring(names), {}
    end

    local entries, diagnostics = {}, {}
    for _, key in ipairs(names) do
        local entry_path = join(trash_path(), key)
        local stat = vim.uv.fs_lstat(entry_path)
        if stat and stat.type == "directory" then
            local entry, err = read_trash_entry(key)
            if entry then
                table.insert(entries, entry)
            else
                table.insert(diagnostics, "skipping trash entry " .. key .. ": " .. tostring(err))
            end
        elseif stat then
            table.insert(diagnostics, "skipping trash entry " .. key .. ": untrusted path")
        end
    end

    table.sort(entries, function(a, b)
        return a.deleted_at > b.deleted_at or (a.deleted_at == b.deleted_at and a.key < b.key)
    end)

    return entries, nil, diagnostics
end

---@param key string
---@return Sess.TrashEntry?, string?
function M.read_trash(key)
    assert_initialized()
    local trusted, trust_err = trusted_dir(trash_path(), "trash directory")
    if not trusted then
        return nil, trust_err
    end
    return read_trash_entry(key)
end

---@param key string
---@param expected Sess.TrashEntry?
---@return boolean, string?, Sess.TrashEntry?
function M.restore(key, expected)
    assert_initialized()

    local trusted, trust_err = trusted_dir(trash_path(), "trash directory")
    if not trusted then
        return false, trust_err
    end
    trusted, trust_err = trusted_dir(sessions_path(), "sessions directory")
    if not trusted then
        return false, trust_err
    end

    local entry, err = M.read_trash(key)
    if not entry then
        return false, err
    end
    if expected and not vim.deep_equal(entry, expected) then
        return false, "deleted session changed during restore: " .. tostring(key)
    end
    local existing, existing_err = M.exists(entry.id)
    if existing then
        return false, "destination session already exists: " .. entry.id
    end
    if existing_err then
        return false, existing_err
    end

    local source = trash_entry_path(key)
    local destination = session_paths(entry.id).dir
    local destination_stat = vim.uv.fs_lstat(destination)
    if destination_stat then
        return false, "untrusted destination session path: " .. destination
    end
    local ok, rename_err = vim.uv.fs_rename(source, destination)
    if not ok then
        return false, rename_err
    end

    return true, nil, entry
end

-- Session creation / deletion

-- Reserve the catalog while checking uniqueness and creating a new record. The
-- lock has an owner record so a process killed after mkdir can be recovered,
-- while a live owner is never stolen.
local held_create_lock
local LOCK_STALE_AFTER = 60

local function lock_owner_path(lock_path)
    return join(lock_path, "owner.json")
end

local function owner_is_live(owner)
    if type(owner) ~= "table" or type(owner.pid) ~= "number" or owner.pid < 1 then
        return false
    end
    if owner.pid == vim.uv.getpid() then
        return true
    end
    local result, kill_err = vim.uv.kill(owner.pid, 0)
    -- libuv bindings have returned either 0 or true for a successful signal
    -- probe. ESRCH proves that the process is gone; permission and other
    -- errors are deliberately treated as live/unknown so a foreign owner is
    -- never stolen merely because it cannot be inspected.
    if result == 0 or result == true then
        return true
    end
    return not tostring(kill_err or ""):match("ESRCH")
end

local function lock_is_old(stat)
    return stat
        and stat.mtime
        and type(stat.mtime.sec) == "number"
        and os.time() - stat.mtime.sec >= LOCK_STALE_AFTER
end

local function remove_stale_lock(lock_path, stat)
    local owner_path = lock_owner_path(lock_path)
    local owner_stat = vim.uv.fs_lstat(owner_path)
    local owner
    local owner_err
    if owner_stat then
        owner, owner_err = read_json(owner_path)
        if owner and owner_is_live(owner) then
            return false, "session creation is already in progress"
        end
        if not owner and not lock_is_old(stat) then
            -- Never steal a fresh lock whose owner cannot be verified. This
            -- covers a live process killed or paused before its owner record
            -- was published; recovery becomes possible after the stale age.
            return false, "session creation lock owner cannot be verified: " .. tostring(owner_err)
        end

        local removed, remove_err = vim.uv.fs_unlink(owner_path)
        if not removed then
            return false, "failed to remove stale session creation lock owner: " .. tostring(remove_err)
        end
    elseif not lock_is_old(stat) then
        -- The lock directory is published only after its owner record is
        -- written. A missing owner on a fresh lock is therefore an in-flight
        -- publication, not permission to steal the lock.
        return false, "session creation lock owner is not yet published"
    end

    local removed, remove_err = vim.uv.fs_rmdir(lock_path)
    if not removed then
        return false, "failed to remove stale session creation lock: " .. tostring(remove_err)
    end
    return true
end

local function acquire_create_lock()
    local lock_path = join(root_path, ".create.lock")
    for _ = 1, 3 do
        local stat = vim.uv.fs_lstat(lock_path)
        if not stat then
            local token = tostring(vim.uv.hrtime()) .. "-" .. tostring(math.random())
            local owner = { pid = vim.uv.getpid(), token = token, created_at = os.time() }
            local made, make_err = vim.uv.fs_mkdir(lock_path, 448)
            if made then
                local wrote, write_err = write_json(lock_owner_path(lock_path), owner)
                if wrote then
                    held_create_lock = owner
                    return true, lock_path
                end

                -- mkdir is the ownership reservation. If publishing metadata
                -- fails, remove it only while it is still empty/owned; any
                -- cleanup failure remains safely recoverable through stale
                -- owner handling rather than being silently ignored.
                local removed, remove_err = vim.uv.fs_unlink(lock_owner_path(lock_path))
                local removed_dir, remove_dir_err = vim.uv.fs_rmdir(lock_path)
                local cleanup = ""
                if not removed and vim.uv.fs_lstat(lock_owner_path(lock_path)) then
                    cleanup = cleanup .. "; failed to clean lock owner: " .. tostring(remove_err)
                end
                if not removed_dir then
                    cleanup = cleanup .. "; failed to clean lock directory: " .. tostring(remove_dir_err)
                end
                return false, "failed to publish session creation lock owner: " .. tostring(write_err) .. cleanup
            end
            stat = vim.uv.fs_lstat(lock_path)
            if not stat then
                return false, "failed to create session creation lock: " .. tostring(make_err)
            end
        end

        if stat.type ~= "directory" then
            return false, "untrusted session creation lock path"
        end
        local recovered, recover_err = remove_stale_lock(lock_path, stat)
        if not recovered then
            return false, recover_err
        end
    end
    return false, "session creation lock changed while recovering"
end

local function release_create_lock(lock_path)
    local owner_path = lock_owner_path(lock_path)
    local owner = read_json(owner_path)
    if not owner or not held_create_lock or owner.token ~= held_create_lock.token then
        return false, "session creation lock owner changed"
    end

    local removed, remove_err = vim.uv.fs_unlink(owner_path)
    if not removed then
        local marker, marker_err = write_json(owner_path, {
            released = true,
            token = held_create_lock.token,
            released_at = os.time(),
        })
        local diagnostic = tostring(remove_err)
        if not marker then
            diagnostic = diagnostic .. "; failed to publish release marker: " .. tostring(marker_err)
        end
        return false, diagnostic
    end

    local released, release_err = vim.uv.fs_rmdir(lock_path)
    if released then
        held_create_lock = nil
        return true
    end

    -- The owner was removed, but a failed rmdir can leave the lock wedged.
    -- Publish a completion tombstone so a later owner can safely recover it.
    local marker, marker_err = write_json(owner_path, {
        released = true,
        token = held_create_lock.token,
        released_at = os.time(),
    })
    local diagnostic = tostring(release_err)
    if not marker then
        diagnostic = diagnostic .. "; failed to publish release marker: " .. tostring(marker_err)
    end
    return false, diagnostic
end

function M.with_create_lock(callback)
    assert_initialized()

    local trusted, trust_err = trusted_dir(root_path, "storage directory")
    if not trusted then
        return false, trust_err
    end

    local acquired, acquire_err = acquire_create_lock()
    if not acquired then
        return false, "session creation is already in progress: " .. tostring(acquire_err)
    end

    local called, first, second, third, fourth = pcall(callback)
    local released, release_err = release_create_lock(acquire_err)
    held_create_lock = nil
    if not released then
        local cleanup = "failed to release session creation lock: " .. tostring(release_err)
        if not called then
            return false, append_error(tostring(first), cleanup)
        end
        if not first then
            -- Failed callbacks expose their primary error in the second slot;
            -- callers do not inspect success-only cleanup diagnostics then.
            return first, append_error(second, cleanup), third, fourth
        end
        -- A committed record/result must not be discarded merely because
        -- cleanup failed. Preserve every callback return value and expose the
        -- cleanup warning in the diagnostics slot.
        return first, second, third, cleanup
    end

    if not called then
        return false, tostring(first)
    end

    return first, second, third, fourth
end

---@param id Sess.SessionId
---@return boolean, string?
function M.create(id)
    assert_initialized()

    local trusted, trust_err = trusted_dir(sessions_path(), "sessions directory")
    if not trusted then
        return false, trust_err
    end

    local valid, err = validate_id(id)
    if not valid then
        return false, err
    end

    local existing, existing_err = M.exists(id)
    if existing then
        return false, "session already exists: " .. id
    end
    if existing_err then
        return false, existing_err
    end

    local paths = session_paths(id)

    local ok = vim.uv.fs_mkdir(paths.dir, 448) -- 0700

    if not ok then
        -- fs_mkdir can fail if the parent disappeared etc.
        return false, "failed to create session directory: " .. paths.dir
    end

    return true
end

---@param id Sess.SessionId
---@param hard boolean?
---@return boolean, string?
function M.delete(id, hard)
    assert_initialized()

    local trusted, trust_err = trusted_dir(sessions_path(), "sessions directory")
    if not trusted then
        return false, trust_err
    end
    if not hard then
        trusted, trust_err = trusted_dir(trash_path(), "trash directory")
        if not trusted then
            return false, trust_err
        end
    end

    local exists, exists_err = M.exists(id)
    if not exists then
        return false, exists_err or ("session does not exist: " .. id)
    end

    local paths = session_paths(id)

    if hard then
        local session_stat = vim.uv.fs_lstat(paths.dir)
        if not session_stat or session_stat.type ~= "directory" then
            return false, "untrusted session path: " .. paths.dir
        end
        if vim.fn.delete(paths.dir, "rf") ~= 0 then
            return false, "failed to permanently delete session: " .. id
        end

        return true
    end

    -- Move the entire session into trash. Avoid replacing a pre-existing entry
    -- if a clock or test double returns the same timestamp twice.
    local timestamp = tostring(os.time())
    local counter = vim.uv.hrtime()
    local destination =
        join(trash_path(), id .. "-" .. timestamp .. "-" .. string.format("%.0f", counter))
    while vim.uv.fs_lstat(destination) do
        counter = counter + 1
        destination =
            join(trash_path(), id .. "-" .. timestamp .. "-" .. string.format("%.0f", counter))
    end

    local ok, err = vim.uv.fs_rename(paths.dir, destination)

    if not ok then
        return false, err
    end

    return true
end

---@param old_id Sess.SessionId
---@param new_id Sess.SessionId
---@return boolean, string?
function M.rename(old_id, new_id)
    assert_initialized()

    local trusted, trust_err = trusted_dir(sessions_path(), "sessions directory")
    if not trusted then
        return false, trust_err
    end

    local valid, err = validate_id(new_id)
    if not valid then
        return false, err
    end

    local old_exists, old_err = M.exists(old_id)
    if not old_exists then
        return false, old_err or ("session does not exist: " .. old_id)
    end

    local new_exists, new_err = M.exists(new_id)
    if new_exists then
        return false, "destination session already exists: " .. new_id
    end
    if new_err then
        return false, new_err
    end

    local old_path = session_paths(old_id).dir
    local new_path = session_paths(new_id).dir

    local ok, rename_err = vim.uv.fs_rename(old_path, new_path)

    if not ok then
        return false, rename_err
    end

    return true
end

-- Metadata

---@param id Sess.SessionId
---@return Sess.SessionMetadata?, string?
function M.read_metadata(id)
    local valid, err = validate_id(id)
    if not valid then
        return nil, err
    end

    local exists, exists_err = M.exists(id)
    if not exists then
        return nil, exists_err or ("session does not exist: " .. id)
    end

    local paths = session_paths(id)

    local data, read_err = read_json(paths.metadata)

    if not data then
        return nil, read_err
    end

    return validate_metadata(data)
end

---@param id Sess.SessionId
---@param metadata Sess.SessionMetadata
---@return boolean, string?
function M.write_metadata(id, metadata)
    if not M.exists(id) then
        return false, "session does not exist: " .. id
    end

    if type(metadata) ~= "table" then
        return false, "session metadata must be a table"
    end

    local copied, copied_metadata = pcall(vim.deepcopy, metadata)
    if not copied then
        return false, "failed to copy session metadata: " .. tostring(copied_metadata)
    end

    if copied_metadata.version == nil then
        copied_metadata.version = consts.get_version()
    end

    local validated_metadata, validation_err = validate_metadata(copied_metadata)
    if not validated_metadata then
        return false, validation_err
    end

    return write_json(session_paths(id).metadata, validated_metadata)
end

---@param id Sess.SessionId
---@param metadata Sess.SessionMetadata
---@return boolean, string?
function M.create_with_metadata(id, metadata)
    local ok, err = M.create(id)

    if not ok then
        return false, err
    end

    ok, err = M.write_metadata(id, metadata)
    if not ok then
        M.delete(id, true)

        return false, err
    end

    return true
end

-- Get session path

---@param id Sess.SessionId
---@return string?, string?
function M.get_session_path(id)
    if not M.exists(id) then
        return nil, "session does not exist: " .. id
    end

    return session_paths(id).session
end

---@param id Sess.SessionId
---@return boolean, string?
function M.validate_snapshot(id)
    local path, err = M.get_session_path(id)
    if not path then
        return false, err
    end

    local stat = vim.uv.fs_lstat(path)
    if not stat or stat.type ~= "file" then
        return false, "session file is not readable: " .. path
    end

    local content, read_err = read_file(path)
    if not content then
        return false, "session file is not readable: " .. tostring(read_err)
    end

    return true
end

-- Inspect the mksession envelope without sourcing or otherwise executing the
-- Vimscript. This is intentionally separate from validate_snapshot(), which
-- remains the lifecycle readability check.
---@param id Sess.SessionId
---@return "available"|"invalid"|"unavailable", string?
function M.inspect_snapshot(id)
    local path, path_err = M.get_session_path(id)
    if not path then
        return "unavailable", path_err
    end

    local stat = vim.uv.fs_lstat(path)
    if not stat or stat.type ~= "file" then
        return "unavailable", "session file is not a regular file: " .. path
    end

    local content, read_err = read_file(path)
    if not content then
        return "unavailable", "failed to read session file: " .. tostring(read_err)
    end
    if content:find("%z") then
        return "invalid", "invalid session snapshot: contains NUL bytes"
    end

    local has_header = content:match("^let%s+SessionLoad%s*=%s*1%s*[\r\n]")
        or content:match("\nlet%s+SessionLoad%s*=%s*1%s*[\r\n]")
    local has_footer = content:match("^unlet%s+SessionLoad%s*$")
        or content:match("\nunlet%s+SessionLoad%s*[\r\n]")
    if not has_header or not has_footer then
        return "invalid", "invalid session snapshot: missing Vim session envelope"
    end

    return "available"
end

-- Session file

---@param id Sess.SessionId
---@return string?, string?
function M.read_session(id)
    if not M.exists(id) then
        return nil, "session does not exist: " .. id
    end

    return read_file(session_paths(id).session)
end

---@param id Sess.SessionId
---@param content string
---@return boolean, string?
function M.write_session(id, content)
    if not M.exists(id) then
        return false, "session does not exist: " .. id
    end

    return write_file_atomic(session_paths(id).session, content)
end

-- Validate IDs before any path construction, even on less common entry points.
M.validate_id = validate_id

for _, name in ipairs({
    "exists",
    "create",
    "replace_snapshot",
    "delete",
    "rename",
    "read_metadata",
    "write_metadata",
    "create_with_metadata",
    "get_session_path",
    "validate_snapshot",
    "inspect_snapshot",
    "read_session",
    "write_session",
}) do
    local operation = M[name]
    M[name] = function(id, ...)
        local valid, err = validate_id(id)
        if not valid then
            if
                name == "read_metadata"
                or name == "get_session_path"
                or name == "read_session"
                or name == "inspect_snapshot"
            then
                return nil, err
            end

            return false, err
        end

        return operation(id, ...)
    end
end

return M
