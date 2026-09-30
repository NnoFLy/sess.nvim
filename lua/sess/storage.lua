local M = {}

local consts = require("sess.consts")
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

local SESSIONS_DIR = "sessions"
local TRASH_DIR = "trash"

local METADATA_FILE = "metadata.json"
local SESSION_FILE = "session.vim"

-- Internal helpers
local validate_id

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
    return vim.uv.fs_stat(path) ~= nil
end

---@param path string
---@return boolean
local function dir_exists(path)
    local stat = vim.uv.fs_stat(path)

    return stat ~= nil and stat.type == "directory"
end

local function trash_entry_path(key)
    if type(key) ~= "string" or key == "" or not key:match("^[%w_.%-]+$") then
        return nil, "invalid trash entry key"
    end

    return join(trash_path(), key)
end

local function ensure_private_dir(path, label)
    if vim.fn.mkdir(path, "p") ~= 1 and not dir_exists(path) then
        return false, "failed to create " .. label .. ": " .. path
    end

    local ok, err = vim.uv.fs_chmod(path, 448) -- 0700
    if not ok then
        return false, "failed to restrict " .. label .. ": " .. tostring(err)
    end

    return true
end

---@param path string
---@return string?, string?
local function read_file(path)
    local file, err = io.open(path, "r")
    if not file then
        return nil, err
    end

    local content, read_err = file:read("*a")
    file:close()

    return content, read_err
end

---@param path string
---@param content string
---@return boolean, string?
local function write_file_atomic(path, content)
    local fd, tmp_path = vim.uv.fs_mkstemp(path .. ".tmp-XXXXXX")
    if not fd then
        return false, tmp_path
    end

    local closed, close_err = vim.uv.fs_close(fd)
    if not closed then
        vim.uv.fs_unlink(tmp_path)

        return false, close_err
    end

    local file, err = io.open(tmp_path, "w")
    if not file then
        vim.uv.fs_unlink(tmp_path)

        return false, err
    end

    local ok, write_err = file:write(content)

    if not ok then
        file:close()
        vim.uv.fs_unlink(tmp_path)

        return false, write_err
    end

    local flush_ok, flush_err = file:flush()
    local close_ok, close_err = file:close()
    if not flush_ok or not close_ok then
        vim.uv.fs_unlink(tmp_path)

        return false, flush_err or close_err
    end

    local rename_ok, rename_err = vim.uv.fs_rename(tmp_path, path)

    if not rename_ok then
        vim.uv.fs_unlink(tmp_path)

        return false, rename_err
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
function M.replace_snapshot(id, generate)
    local path = session_paths(id).session
    local fd, temporary = vim.uv.fs_mkstemp(path .. ".tmp-XXXXXX")
    if not fd then
        return false, temporary
    end

    vim.uv.fs_close(fd)

    local ok, err = pcall(generate, temporary)
    if not ok then
        vim.uv.fs_unlink(temporary)

        return false, tostring(err)
    end

    local renamed, rename_err = vim.uv.fs_rename(temporary, path)
    if not renamed then
        vim.uv.fs_unlink(temporary)

        return false, rename_err
    end

    return true
end

-- Initialization

---@param path string
---@return boolean, string?
function M.init(path)
    if type(path) ~= "string" or vim.trim(path) == "" then
        return false, "storage path must be a non-empty string"
    end

    root_path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))

    local ok, err = ensure_private_dir(root_path, "storage directory")
    if not ok then
        return false, err
    end

    ok, err = ensure_private_dir(sessions_path(), "sessions directory")
    if not ok then
        return false, err
    end

    ok, err = ensure_private_dir(trash_path(), "trash directory")
    if not ok then
        return false, err
    end

    return true
end

function M.root()
    return root_path
end

-- Marks are a separate registry: reassignment never rewrites session records.
function M.validate_mark(mark)
    if type(mark) ~= "string" or not mark:match("^[a-z0-9]$") then
        return false, "mark must be one lowercase ASCII letter or digit"
    end
    return true
end

local function validate_marks(data)
    if type(data) ~= "table" or data.version ~= 1 then
        return nil, "unsupported mark registry version"
    end
    if type(data.marks) ~= "table" then
        return nil, "mark registry must contain a marks object"
    end
    for mark, id in pairs(data.marks) do
        local valid, err = M.validate_mark(mark)
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

    local ok, entries = pcall(vim.fn.readdir, sessions_path())
    if not ok then
        return {}, tostring(entries)
    end

    ---@type Sess.SessionId[]
    local result = {}

    for _, name in ipairs(entries) do
        if dir_exists(join(sessions_path(), name)) then
            table.insert(result, name)
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

    local stat, err, code = vim.uv.fs_stat(session_paths(id).dir)
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

    if not dir_exists(path) then
        return nil, "trash entry does not exist: " .. key
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

    local ok, names = pcall(vim.fn.readdir, trash_path())
    if not ok then
        return {}, tostring(names), {}
    end

    local entries, diagnostics = {}, {}
    for _, key in ipairs(names) do
        if dir_exists(join(trash_path(), key)) then
            local entry, err = read_trash_entry(key)
            if entry then
                table.insert(entries, entry)
            else
                table.insert(diagnostics, "skipping trash entry " .. key .. ": " .. tostring(err))
            end
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
    return read_trash_entry(key)
end

---@param key string
---@return boolean, string?, Sess.TrashEntry?
function M.restore(key)
    assert_initialized()

    local entry, err = M.read_trash(key)
    if not entry then
        return false, err
    end
    if M.exists(entry.id) then
        return false, "destination session already exists: " .. entry.id
    end

    local source = trash_entry_path(key)
    local destination = session_paths(entry.id).dir
    local ok, rename_err = vim.uv.fs_rename(source, destination)
    if not ok then
        return false, rename_err
    end

    return true, nil, entry
end

-- Session creation / deletion

---@param id Sess.SessionId
---@return boolean, string?
function M.create(id)
    assert_initialized()

    local valid, err = validate_id(id)
    if not valid then
        return false, err
    end

    if M.exists(id) then
        return false, "session already exists: " .. id
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

    if not M.exists(id) then
        return false, "session does not exist: " .. id
    end

    local paths = session_paths(id)

    if hard then
        if vim.fn.delete(paths.dir, "rf") ~= 0 then
            return false, "failed to permanently delete session: " .. id
        end

        return true
    end

    -- Move the entire session into trash. Avoid replacing a pre-existing entry
    -- if a clock or test double returns the same timestamp twice.
    local timestamp = tostring(os.time())
    local counter = vim.uv.hrtime()
    local destination = join(trash_path(), id .. "-" .. timestamp .. "-" .. tostring(counter))
    while vim.uv.fs_stat(destination) do
        counter = counter + 1
        destination = join(trash_path(), id .. "-" .. timestamp .. "-" .. tostring(counter))
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

    local valid, err = validate_id(new_id)
    if not valid then
        return false, err
    end

    if not M.exists(old_id) then
        return false, "session does not exist: " .. old_id
    end

    if M.exists(new_id) then
        return false, "destination session already exists: " .. new_id
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
    "read_session",
    "write_session",
}) do
    local operation = M[name]
    M[name] = function(id, ...)
        local valid, err = validate_id(id)
        if not valid then
            if name == "read_metadata" or name == "get_session_path" or name == "read_session" then
                return nil, err
            end

            return false, err
        end

        return operation(id, ...)
    end
end

return M
