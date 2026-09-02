local M = {}

local log = require("sess.log")
local consts = require("sess.consts")

---@class Sess.Index
---@field version Sess.Version
---@field sessions table<Sess.SessionId, Sess.IndexEntry>

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
local INDEX_FILE = "index.json"

-- Internal helpers

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

---@return string
local function index_path()
    assert_initialized()
    return join(root_path, INDEX_FILE)
end

---@param id Sess.SessionId
---@return Sess.SessionPaths
local function session_paths(id)
    assert_initialized()

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

---@param path string
---@return string?, string?
local function read_file(path)
    local file, err = io.open(path, "r")
    if not file then
        return nil, err
    end

    local content = file:read("*a")
    file:close()

    return content
end

---@param path string
---@param content string
---@return boolean, string?
local function write_file_atomic(path, content)
    local tmp_path = path .. ".tmp"

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

    file:flush()
    file:close()

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
local function validate_id(id)
    if id == "" then
        return false, "session id cannot be empty"
    end

    -- Prevent escaping sessions/<id>.
    if id:find("/", 1, true)
        or id:find("\\", 1, true)
        or id == "."
        or id == ".."
    then
        return false, "invalid session id: " .. id
    end

    return true
end

---@param id Sess.SessionId
local function create_session(id)
    local path = session_paths(id).session
    local ok, err = pcall(function()
        vim.cmd({
            cmd = "mksession",
            bang = true,
            args = { path },
        })
    end)
    if not ok then
        return false, tostring(err)
    end
    return true
end

-- Initialization

---@param path string
---@return boolean, string?
function M.init(path)
    root_path = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))

    vim.fn.mkdir(root_path, "p")

    if not dir_exists(root_path) then
        return false, "storage path is not a directory: " .. root_path
    end

    local ok, err = pcall(function()
        vim.fn.mkdir(sessions_path(), "p")
        vim.fn.mkdir(trash_path(), "p")
    end)

    if not ok then
        return false, tostring(err)
    end

    return true
end

-- Session discovery

---@return Sess.SessionId[], string?
function M.list()
    assert_initialized()

    local entries = vim.fn.readdir(sessions_path())

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

    return dir_exists(session_paths(id).dir)
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

---@param id string
---@return boolean, string?
function M.update(id)
    local ok, err = create_session(id)
    if not ok then
        return false, err
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
        local ok, err = vim.uv.fs_unlink(paths.metadata)

        if not ok and file_exists(paths.metadata) then
            return false, err
        end

        ok, err = vim.uv.fs_unlink(paths.session)

        if not ok and file_exists(paths.session) then
            return false, err
        end

        local dir_ok, dir_err = vim.uv.fs_rmdir(paths.dir)

        if not dir_ok then
            return false, dir_err
        end

        return true
    end

    -- Move the entire session into trash.
    local destination = join(
        trash_path(),
        id .. "-" .. tostring(os.time())
    )

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
            return nil, string.format(
                "invalid session metadata: field %s must be %s",
                field,
                expected_type
            )
        end
    end

    if data.version ~= consts.get_version() then
        return nil, "unsupported session metadata version: " .. tostring(data.version)
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

    ok, err = create_session(id)
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

-- Index

---@return Sess.Index?, string?
function M.read_index()
    local path = index_path()

    if not file_exists(path) then
        return {
            version = consts.get_version(),
            sessions = {},
        }
    end

    local data, err = read_json(path)

    if not data then
        return nil, err
    end

    return data --[[@as Sess.Index]]
end

---@param index Sess.Index
---@return boolean, string?
function M.write_index(index)
    index.version = index.version or consts.get_version()

    return write_json(index_path(), index)
end

---@return Sess.Index, string?
function M.rebuild_index()
    local ids, err = M.list()

    if err then
        return {
            version = consts.get_version(),
            sessions = {},
        }, err
    end

    ---@type Sess.Index
    local index = {
        version = consts.get_version(),
        sessions = {},
    }

    for _, id in ipairs(ids) do
        local metadata, metadata_err = M.read_metadata(id)

        if metadata then
            index.sessions[id] = {
                name = metadata.name,
                cwd = metadata.cwd,
                last_used_at = metadata.last_used_at,
                pinned = metadata.pinned,
            }
        else
            log.warn(
                "failed to read metadata for session "
                    .. id
                    .. ": "
                    .. tostring(metadata_err)
            )
        end
    end

    return index
end

---@return boolean, string?
function M.sync_index()
    local index, err = M.rebuild_index()

    if err then
        return false, err
    end

    return M.write_index(index)
end

return M
