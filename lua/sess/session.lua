local M = {}

local storage = require("sess.storage")
local consts = require("sess.consts")

local function now()
    return os.time()
end

local function current_cwd()
    return vim.fs.normalize(vim.fn.fnamemodify(vim.fn.getcwd(), ":p"))
end

local function normalize_cwd(cwd)
    if type(cwd) ~= "string" or vim.trim(cwd) == "" then
        return nil
    end
    return vim.fs.normalize(vim.fn.fnamemodify(cwd, ":p"))
end

local function default_name(cwd)
    cwd = vim.fs.normalize(cwd)
    if cwd == "/" then
        return "root"
    end

    local name = vim.fn.fnamemodify(cwd, ":t")
    return name ~= "" and name or "session"
end

local function normalize_name(name)
    if type(name) ~= "string" then
        return nil
    end

    name = vim.trim(name)
    return name ~= "" and name or nil
end

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

local function unique_name(name)
    local normalized = normalize_name(name) or "session"
    local lower = normalized:lower()
    local used = {}

    local sessions, err = M.list()
    if err then
        return nil, err
    end

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

---@param cwd Sess.Cwd
---@return Sess.Session?, string?
function M.get_by_path(cwd)
    cwd = normalize_cwd(cwd)
    if not cwd then
        return nil, "working directory is required"
    end

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
    name = normalize_name(name)
    if not name then
        return nil, "session name cannot be empty"
    end

    local sessions, err = M.list()
    if err then
        return nil, err
    end

    local normalized = name:lower()
    for _, session in ipairs(sessions) do
        if session.metadata.name:lower() == normalized then
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
    if not cwd then
        return nil, "working directory is required"
    end
    if vim.fn.isdirectory(cwd) == 0 then
        return nil, "directory does not exist: " .. cwd
    end

    local existing, err = M.get_by_path(cwd)
    if err then
        return nil, err
    end
    if existing then
        return nil, "session already exists for directory: " .. cwd
    end

    local explicit_name = opts.name ~= nil
    local name
    if explicit_name then
        name = normalize_name(opts.name)
        if not name then
            return nil, "session name cannot be empty"
        end
    else
        name, err = unique_name(default_name(cwd))
        if not name then
            return nil, err
        end
    end

    if explicit_name then
        local by_name, name_err = M.get_by_name(name)
        if name_err then
            return nil, name_err
        end
        if by_name then
            return nil, "session name already exists: " .. name
        end
    end

    local id = opts.id
    if id == nil then
        id = vim.fn.sha256(
            cwd .. "\0" .. tostring(now()) .. "\0" .. tostring(vim.uv.hrtime())
        ):sub(1, 16)
    elseif type(id) ~= "string" or vim.trim(id) == "" then
        return nil, "session id cannot be empty"
    end

    local metadata = {
        version = consts.get_version(),
        name = name,
        cwd = cwd,
        created_at = now(),
        last_used_at = now(),
        pinned = false,
    }

    local ok, create_err = storage.create_with_metadata(id, metadata)
    if not ok then
        return nil, create_err
    end

    return {
        id = id,
        metadata = metadata,
    }
end

---@param id Sess.SessionId
---@return Sess.Session?, string?
function M.get(id)
    if type(id) ~= "string" or vim.trim(id) == "" then
        return nil, "session id is required"
    end
    return read_session(id)
end

---@return Sess.Session[], string?
function M.list()
    local ids, err = storage.list()
    if err then
        return {}, err
    end

    local sessions = {}
    local first_error
    for _, id in ipairs(ids) do
        local item, item_err = read_session(id)
        if item then
            table.insert(sessions, item)
        elseif not first_error then
            first_error = "failed to load session " .. id .. ": " .. tostring(item_err)
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

    return sessions, first_error
end

---@param id Sess.SessionId
---@param name string
---@return Sess.Session?, string?
function M.rename(id, name)
    name = normalize_name(name)
    if not name then
        return nil, "session name cannot be empty"
    end

    local item, err = read_session(id)
    if not item then
        return nil, err
    end

    local existing, name_err = M.get_by_name(name)
    if name_err then
        return nil, name_err
    end
    if existing and existing.id ~= id then
        return nil, "session name already exists: " .. name
    end

    item.metadata.name = name
    local ok, save_err = storage.write_metadata(id, item.metadata)
    if not ok then
        return nil, save_err
    end

    return item
end

---@param id Sess.SessionId
---@param pinned boolean
---@return Sess.Session?, string?
function M.set_pinned(id, pinned)
    local item, err = read_session(id)
    if not item then
        return nil, err
    end

    item.metadata.pinned = pinned
    local ok, save_err = storage.write_metadata(id, item.metadata)
    if not ok then
        return nil, save_err
    end

    return item
end

---@param id Sess.SessionId
---@return Sess.Session?, string?
function M.toggle_pinned(id)
    local item, err = read_session(id)
    if not item then
        return nil, err
    end

    return M.set_pinned(id, not item.metadata.pinned)
end

---@param id Sess.SessionId
---@return Sess.Session?, string?
function M.touch(id)
    local item, err = read_session(id)
    if not item then
        return nil, err
    end

    item.metadata.last_used_at = now()
    local ok, save_err = storage.write_metadata(id, item.metadata)
    if not ok then
        return nil, save_err
    end

    return item
end

---@param id Sess.SessionId
---@param permanent boolean?
---@return boolean, string?
function M.delete(id, permanent)
    return storage.delete(id, permanent)
end

---@param id Sess.SessionId
---@return boolean, string?
function M.save(id)
    local item, err = read_session(id)
    if not item then
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

    local ok, source_err = pcall(vim.cmd, { cmd = "source", args = { session_path } })
    if not ok then
        return false, tostring(source_err)
    end

    -- The session is already loaded successfully; failure to update metadata
    -- must not turn a successful load into a reported load failure.
    M.touch(id)
    return true
end

---@return Sess.Session[], string?
function M.pinned()
    local sessions, err = M.list()
    local result = {}
    for _, item in ipairs(sessions) do
        if item.metadata.pinned then
            table.insert(result, item)
        end
    end
    return result, err
end

M.find_by_name = M.get_by_name
M.find_by_cwd = M.get_by_path
M.get_all = M.list

return M
