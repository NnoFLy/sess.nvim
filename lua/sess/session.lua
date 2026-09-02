local M = {}

local storage = require("sess.storage")
local log = require("sess.log")

local VERSION = 1

---@return Sess.Timestamp
local function now()
    return os.time()
end

---@return Sess.Cwd
local function current_cwd()
    return vim.fs.normalize(vim.fn.fnamemodify(vim.fn.getcwd(), ":p"))
end

---@param cwd string
---@return Sess.Cwd
local function normalize_cwd(cwd)
    return vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p"))
end

---@param cwd string
---@return string
local function default_name(cwd)
    cwd = vim.fs.normalize(cwd)

    if cwd == "/" then
        return "root"
    end

    local name = vim.fn.fnamemodify(cwd, ":t")
    return name ~= "" and name or "session"
end

---@param name string
---@return string
local function normalize_name(name)
    name = vim.trim(name)
    return name ~= "" and name or "session"
end

---@param name string
---@return string
local function unique_name(name)
    local normalized = normalize_name(name)
    local lower = normalized:lower()

    local used = {}
    local sessions = M.list() or {}
    for _, existing in ipairs(sessions) do
        used[existing.metadata.name:lower()] = true
    end

    if not used[lower] then
        return normalized
    end

    local suffix = 2
    while used[(normalized .. " (" .. suffix .. ")"):lower()] do
        suffix = suffix + 1
    end

    return normalized .. " (" .. suffix .. ")"
end

---@param id Sess.SessionId
---@return Sess.Session?, string?
local function read_session(id)
    local metadata, err = storage.read_metadata(id)
    if not metadata then
        return nil, err
    end

    return {
        id = id,
        metadata = metadata,
    }
end

---@param cwd Sess.Cwd
---@return Sess.Session?, string?
function M.get_by_path(cwd)
    cwd = normalize_cwd(cwd)

    local sessions, err = M.list()
    if err then
        return nil, err
    end

    for _, session in ipairs(sessions) do
        if vim.fs.normalize(session.metadata.cwd) == cwd then
            return session
        end
    end

    return nil
end

---@param name string
---@return Sess.Session?, string?
function M.get_by_name(name)
    local sessions, err = M.list()
    if err then
        return nil, err
    end

    for _, session in ipairs(sessions) do
        if session.metadata.name:lower() == vim.trim(name):lower() then
            return session
        end
    end

    return nil
end

---@param opts Sess.CreateOpts?
---@return Sess.Session?, string?
function M.create(opts)
    opts = opts or {}

    local cwd = normalize_cwd(opts.cwd or current_cwd())
    if vim.fn.isdirectory(cwd) == 0 then
        return nil, "directory does not exist: " .. cwd
    end

    local explicit_name = opts.name ~= nil
    local name = explicit_name and normalize_name(opts.name) or unique_name(default_name(cwd))

    if M.get_by_path(cwd) then
        return nil, "session already exists for directory: " .. cwd
    end

    if explicit_name then
        local existing = M.get_by_name(name)
        if existing then
            return nil, "session name already exists: " .. name
        end
    end

    local id = opts.id or vim.fn.sha256(
        cwd .. "\0" .. tostring(now()) .. "\0" .. tostring(math.random())
    ):sub(1, 16)

    ---@type Sess.SessionMetadata
    local metadata = {
        version = VERSION,
        name = name,
        cwd = cwd,
        created_at = now(),
        last_used_at = now(),
        pinned = false,
    }

    local ok, err = storage.create_with_metadata(id, metadata)
    if not ok then
        return nil, err
    end

    local index_ok, index_err = storage.sync_index()
    if not index_ok then
        log.warn("failed to update session index: " .. tostring(index_err))
    end

    return {
        id = id,
        metadata = metadata,
    }
end

---@param id Sess.SessionId
---@return Sess.Session?, string?
function M.get(id)
    return read_session(id)
end

---@return Sess.Session[], string?
function M.list()
    local ids, err = storage.list()
    if err then
        return {}, err
    end

    ---@type Sess.Session[]
    local sessions = {}

    for _, id in ipairs(ids) do
        local session, session_err = read_session(id)
        if session then
            table.insert(sessions, session)
        else
            log.warn(
                "failed to load session " .. id .. ": " .. tostring(session_err)
            )
        end
    end

    table.sort(sessions, function(a, b)
        local an = a.metadata.name:lower()
        local bn = b.metadata.name:lower()
        if an ~= bn then
            return an < bn
        end
        return a.id < b.id
    end)

    return sessions
end

---@param name string
---@return Sess.Session?, string?
function M.find_by_name(name)
    return M.get_by_name(name)
end

---@param cwd Sess.Cwd
---@return Sess.Session?, string?
function M.find_by_cwd(cwd)
    return M.get_by_path(cwd)
end

---@param id Sess.SessionId
---@param predicate fun(session: Sess.Session): boolean
---@return Sess.Session?
function M.find(id, predicate)
    local session = read_session(id)
    if session and predicate(session) then
        return session
    end
    return nil
end

---@param id Sess.SessionId
---@param name string
---@return Sess.Session?, string?
function M.rename(id, name)
    local session, err = read_session(id)
    if not session then
        return nil, err
    end

    name = normalize_name(name)

    local existing = M.get_by_name(name)
    if existing and existing.id ~= id then
        return nil, "session name already exists: " .. name
    end

    session.metadata.name = name

    local ok, save_err = storage.write_metadata(id, session.metadata)
    if not ok then
        return nil, save_err
    end

    local index_ok, index_err = storage.sync_index()
    if not index_ok then
        log.warn("failed to update session index: " .. tostring(index_err))
    end

    return session
end

---@param id Sess.SessionId
---@param pinned boolean
---@return Sess.Session?, string?
function M.set_pinned(id, pinned)
    local session, err = read_session(id)
    if not session then
        return nil, err
    end

    session.metadata.pinned = pinned

    local ok, save_err = storage.write_metadata(id, session.metadata)
    if not ok then
        return nil, save_err
    end

    local index_ok, index_err = storage.sync_index()
    if not index_ok then
        log.warn("failed to update session index: " .. tostring(index_err))
    end

    return session
end

---@param id Sess.SessionId
---@return Sess.Session?, string?
function M.toggle_pinned(id)
    local session, err = read_session(id)
    if not session then
        return nil, err
    end

    return M.set_pinned(id, not session.metadata.pinned)
end

---@param id Sess.SessionId
---@return Sess.Session?, string?
function M.touch(id)
    local session, err = read_session(id)
    if not session then
        return nil, err
    end

    session.metadata.last_used_at = now()

    local ok, save_err = storage.write_metadata(id, session.metadata)
    if not ok then
        return nil, save_err
    end

    local index_ok, index_err = storage.sync_index()
    if not index_ok then
        log.warn("failed to update session index: " .. tostring(index_err))
    end

    return session
end

---@param id Sess.SessionId
---@param permanent boolean?
---@return boolean, string?
function M.delete(id, permanent)
    local ok, err = storage.delete(id, permanent)
    if not ok then
        return false, err
    end

    local index_ok, index_err = storage.sync_index()
    if not index_ok then
        log.warn("failed to update session index: " .. tostring(index_err))
    end

    return true
end

---@param id Sess.SessionId
---@return boolean, string?
function M.save(id)
    local session, err = read_session(id)
    if not session then
        return false, err
    end

    local ok, save_err = storage.update(id)
    if not ok then
        return false, save_err
    end

    local touched, touch_err = M.touch(id)
    if not touched then
        return false, touch_err
    end

    return true
end

---@param id Sess.SessionId
---@return boolean, string?
function M.load_session(id)
    local session_path, err = storage.get_session_path(id)
    if not session_path then
        return false, err
    end

    if not vim.uv.fs_stat(session_path) then
        return false, "session file does not exist: " .. session_path
    end

    local ok, source_err = pcall(function()
        vim.cmd({ cmd = "source", args = { session_path } })
    end)
    if not ok then
        return false, tostring(source_err)
    end

    local _, touch_err = M.touch(id)
    if touch_err then
        log.warn("failed to update session usage time: " .. tostring(touch_err))
    end

    return true
end

---@return Sess.Session?, string?
function M.latest()
    local sessions, err = M.list()
    if err then
        return nil, err
    end

    local latest
    for _, session in ipairs(sessions) do
        if not latest or session.metadata.last_used_at > latest.metadata.last_used_at then
            latest = session
        end
    end

    return latest
end

---@return Sess.Session[], string?
function M.pinned()
    local sessions, err = M.list()
    if err then
        return {}, err
    end

    local result = {}
    for _, session in ipairs(sessions) do
        if session.metadata.pinned then
            table.insert(result, session)
        end
    end

    return result
end

M.get_all = M.list

return M
