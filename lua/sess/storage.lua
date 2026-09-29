local M = {}

local consts = require("sess.consts")

---@class Sess.SessionFiles
---@field metadata string
---@field session string

---@class Sess.SessionPaths
---@field dir string
---@field metadata string
---@field session string

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
    local tmp_path = path .. ".tmp-" .. tostring(vim.uv.hrtime())

    local file, err = io.open(tmp_path, "w")
    if not file then
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

    -- Move the entire session into trash.
    local destination =
        join(trash_path(), id .. "-" .. tostring(os.time()) .. "-" .. tostring(vim.uv.hrtime()))

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

    if vim.trim(data.cwd) == "" or vim.fs.normalize(vim.fn.fnamemodify(data.cwd, ":p")) == "" then
        return nil, "invalid session metadata: field cwd must be a non-empty path"
    end

    if data.created_at < 0 or data.last_used_at < 0 then
        return nil, "invalid session metadata: timestamps cannot be negative"
    end

    return data --[[@as Sess.SessionMetadata]]
end

---@param id Sess.SessionId
---@param metadata Sess.SessionMetadata
---@return boolean, string?
function M.write_metadata(id, metadata)
    if not M.exists(id) then
        return false, "session does not exist: " .. id
    end

    metadata.version = metadata.version or consts.get_version()

    return write_json(session_paths(id).metadata, metadata)
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
