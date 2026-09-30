local M = {}

local mark_rules = require("sess.mark")
local storage = require("sess.storage")
local consts = require("sess.consts")
local paths = require("sess.path")

local function now()
    return os.time()
end

local function normalize_cwd(cwd)
    return paths.identity(cwd)
end

local function current_cwd()
    return normalize_cwd(vim.fn.getcwd())
end

local function same_cwd(left, right)
    return normalize_cwd(left) == normalize_cwd(right)
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

local function unique_name(name, sessions)
    local normalized = normalize_name(name) or "session"
    local lower = normalized:lower()
    local used = {}

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

local function lookup(sessions, diagnostics, description, predicate)
    local match

    for _, session in ipairs(sessions) do
        if predicate(session) then
            if match then
                return nil, "ambiguous session target: " .. description, diagnostics
            end

            match = session
        end
    end

    return match, nil, diagnostics
end

---@param cwd Sess.Cwd
---@return Sess.Session?, string?, string[]
function M.get_by_path(cwd)
    cwd = normalize_cwd(cwd)
    if not cwd then
        return nil, "working directory is required", {}
    end

    local sessions, err, diagnostics = M.list()
    if err then
        return nil, err, diagnostics
    end

    return lookup(
        sessions,
        diagnostics,
        "working directory " .. cwd,
        function(session)
            return same_cwd(session.metadata.cwd, cwd)
        end
    )
end

---@param name string
---@return Sess.Session?, string?, string[]
function M.get_by_name(name)
    name = normalize_name(name)
    if not name then
        return nil, "session name cannot be empty", {}
    end

    local sessions, err, diagnostics = M.list()
    if err then
        return nil, err, diagnostics
    end

    local normalized = name:lower()
    return lookup(sessions, diagnostics, "name " .. name, function(session)
        return session.metadata.name:lower() == normalized
    end)
end

---@param opts Sess.CreateOpts?
---@return Sess.Session?, string?
function M.prepare_create(opts)
    opts = opts or {}
    if type(opts) ~= "table" then
        return nil, "create options must be a table"
    end

    local sessions, scan_err, diagnostics = M.list()
    if scan_err or #diagnostics > 0 then
        return nil, scan_err or ("cannot verify uniqueness: " .. table.concat(diagnostics, "; "))
    end

    if opts.id ~= nil then
        local valid, id_err = storage.validate_id(opts.id)
        if not valid then
            return nil, id_err
        end

        if storage.exists(opts.id) then
            return nil, "session already exists: " .. opts.id
        end
    end

    local cwd = normalize_cwd(opts.cwd or current_cwd())
    if not cwd then
        return nil, "working directory is required"
    end

    if vim.fn.isdirectory(cwd) == 0 then
        return nil, "directory does not exist: " .. cwd
    end

    for _, existing in ipairs(sessions) do
        if same_cwd(existing.metadata.cwd, cwd) then
            return nil, "session already exists for directory: " .. cwd
        end
    end

    local name
    if opts.name ~= nil then
        name = normalize_name(opts.name)
        if not name then
            return nil, "session name cannot be empty"
        end

        for _, existing in ipairs(sessions) do
            if existing.metadata.name:lower() == name:lower() then
                return nil, "session name already exists: " .. name
            end
        end
    else
        name = unique_name(default_name(cwd), sessions)
    end

    local id = opts.id
    if id == nil then
        local seed = cwd .. "\0" .. tostring(now()) .. "\0" .. tostring(vim.uv.hrtime())
        id = vim.fn.sha256(seed):sub(1, 16)
    end

    local metadata = {
        version = consts.get_version(),
        name = name,
        cwd = cwd,
        created_at = now(),
        last_used_at = now(),
        pinned = false,
    }

    return { id = id, metadata = metadata }
end

function M.create(opts)
    local item, err = M.prepare_create(opts)
    if not item then
        return nil, err
    end

    local ok, create_err = storage.create_with_metadata(item.id, item.metadata)
    if not ok then
        return nil, create_err
    end

    return item
end

---@param id Sess.SessionId
---@return Sess.Session?, string?
function M.get(id)
    if type(id) ~= "string" or vim.trim(id) == "" then
        return nil, "session id is required"
    end

    local valid, err = storage.validate_id(id)
    if not valid then
        return nil, err, "invalid-target"
    end

    local exists, exists_err = storage.exists(id)
    if exists_err then
        return nil, exists_err, "storage"
    end

    if not exists then
        return nil, nil, "not-found"
    end

    return read_session(id)
end

---@return Sess.Session[], string?, string[]
function M.list()
    local ids, err = storage.list()
    if err then
        return {}, err, {}
    end

    local sessions = {}
    local diagnostics = {}

    for _, id in ipairs(ids) do
        local called, item, item_err = pcall(read_session, id)
        if called and item then
            table.insert(sessions, item)
        else
            local load_err = called and item_err or item
            table.insert(diagnostics, "failed to load session " .. id .. ": " .. tostring(load_err))
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

    return sessions, nil, diagnostics
end

---@param id Sess.SessionId
---@param name string
---@return Sess.Session?, string?
function M.rename(id, name)
    local sessions, scan_err, diagnostics = M.list()
    if scan_err or #diagnostics > 0 then
        return nil, scan_err or ("cannot verify uniqueness: " .. table.concat(diagnostics, "; "))
    end

    name = normalize_name(name)
    if not name then
        return nil, "session name cannot be empty"
    end

    local item, err = read_session(id)
    if not item then
        return nil, err
    end

    for _, existing in ipairs(sessions) do
        if existing.metadata.name:lower() == name:lower() and existing.id ~= id then
            return nil, "session name already exists: " .. name
        end
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

---@return Sess.DeletedSession[], string?, string[]
function M.list_deleted()
    return storage.list_trash()
end

---@param target string
---@return Sess.DeletedSession?, string?, string?
function M.resolve_deleted(target)
    if type(target) ~= "string" or vim.trim(target) == "" then
        return nil, "invalid deleted session target", "invalid-target"
    end

    target = vim.trim(target)
    local target_name = target:lower()
    local entries, list_err, diagnostics = M.list_deleted()
    if list_err then
        return nil, list_err, "storage"
    end

    local match
    for _, entry in ipairs(entries) do
        if entry.key == target or entry.id == target or entry.metadata.name:lower() == target_name then
            if match then
                return nil, "deleted session target is ambiguous: " .. target, "ambiguous"
            end
            match = entry
        end
    end

    if match then
        return match
    end

    if #diagnostics > 0 then
        return nil, "deleted session not found: " .. target .. " (" .. table.concat(diagnostics, "; ") .. ")", "not-found"
    end
    return nil, "deleted session not found: " .. target, "not-found"
end

---@param key string
---@return Sess.Session?, string?
function M.restore(key)
    local entry, err = storage.read_trash(key)
    if not entry then
        return nil, err
    end

    local sessions, scan_err, diagnostics = M.list()
    if scan_err or #diagnostics > 0 then
        return nil, scan_err or ("cannot verify uniqueness: " .. table.concat(diagnostics, "; "))
    end

    local name = entry.metadata.name:lower()
    for _, existing in ipairs(sessions) do
        if existing.metadata.name:lower() == name then
            return nil, "session name already exists: " .. entry.metadata.name
        end
        if same_cwd(existing.metadata.cwd, entry.metadata.cwd) then
            return nil, "session already exists for directory: " .. entry.metadata.cwd
        end
    end

    local ok, restore_err = storage.restore(key)
    if not ok then
        return nil, restore_err
    end
    return { id = entry.id, metadata = entry.metadata }
end

-- Stale owners stay queryable until explicitly replaced or unmarked.
local function stale_mark_error(mark, id, err)
    return "stale mark @" .. mark .. ": " .. (err or ("session not found: " .. id))
end

function M.list_marks()
    local marks, err = storage.read_marks()
    if not marks then
        return {}, err, {}
    end
    local entries, diagnostics = {}, {}
    for mark, id in pairs(marks) do
        local item, get_err = M.get(id)
        local stale_err
        if not item then
            stale_err = stale_mark_error(mark, id, get_err)
            diagnostics[#diagnostics + 1] = stale_err
        end
        entries[#entries + 1] = {
            mark = mark,
            id = id,
            session = item,
            stale = not item,
            error = stale_err,
        }
    end
    table.sort(entries, function(a, b)
        return a.mark < b.mark
    end)
    table.sort(diagnostics)
    return entries, nil, diagnostics
end

function M.get_by_mark(mark)
    local valid, err = mark_rules.validate(mark)
    if not valid then
        return nil, err, {}
    end
    local marks, read_err = storage.read_marks()
    if not marks then
        return nil, read_err, {}
    end
    local id = marks[mark]
    if not id then
        return nil, "mark not found: @" .. mark, {}
    end
    local item, get_err = M.get(id)
    if not item then
        return nil, stale_mark_error(mark, id, get_err), {}
    end
    return item, nil, {}
end

-- Resolve identity without editor side effects. Never trust caller metadata.
function M.resolve(target)
    if type(target) == "table" then
        local valid, err = storage.validate_id(target.id)
        if not valid or type(target.metadata) ~= "table" then
            return nil, err or "session target must include metadata", "invalid-target"
        end

        local item, get_err = M.get(target.id)

        return item,
            get_err or (not item and ("session not found: " .. target.id) or nil),
            get_err and "storage" or (not item and "not-found" or nil)
    end

    if type(target) ~= "string" or vim.trim(target) == "" then
        return nil, "invalid session target", "invalid-target"
    end

    target = vim.trim(target)
    if target:sub(1, 1) == "@" then
        local item, err, diagnostics = M.get_by_mark(target:sub(2))
        local reason
        if not item then
            reason = "mark"
        end
        return item, err, reason, diagnostics
    end

    -- IDs are unambiguous; look them up before scanning the catalog. This path
    -- is also used by the active-agent status poller.
    if storage.validate_id(target) then
        local item, get_err = M.get(target)
        if item then
            return item
        end
        if get_err then
            return nil, get_err, "storage"
        end
    end

    local items, list_err, diagnostics = M.list()
    if list_err then
        return nil, list_err, "storage"
    end

    local name_match, name_err = lookup(
        items,
        diagnostics,
        "name " .. target,
        function(item)
            return item.metadata.name:lower() == target:lower()
        end
    )
    if name_err then
        return nil, name_err, "ambiguous", diagnostics
    end
    if name_match then
        return name_match, nil, nil, diagnostics
    end

    local cwd = normalize_cwd(target)
    if cwd then
        local path_match, path_err = lookup(
            items,
            diagnostics,
            "working directory " .. cwd,
            function(item)
                return same_cwd(item.metadata.cwd, cwd)
            end
        )
        if path_err then
            return nil, path_err, "ambiguous", diagnostics
        end
        if path_match then
            return path_match, nil, nil, diagnostics
        end
    end

    if #diagnostics > 0 then
        return nil,
            "cannot resolve target in damaged store: " .. table.concat(diagnostics, "; "),
            "storage",
            diagnostics
    end

    return nil, "session not found: " .. target, "not-found", diagnostics
end

---@return Sess.Session[], string?
function M.pinned()
    local sessions, err, diagnostics = M.list()
    local result = {}

    for _, item in ipairs(sessions) do
        if item.metadata.pinned then
            table.insert(result, item)
        end
    end

    return result, err, diagnostics
end

return M
