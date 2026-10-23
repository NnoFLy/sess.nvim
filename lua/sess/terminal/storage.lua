local M = {}
local uv = vim.uv
local MAX_BYTES = 1024 * 1024

function M.valid_id(id)
    return type(id) == "string" and id:match("^[a-f0-9]+$") ~= nil and #id == 32
end

function M.token()
    local fd, err = uv.fs_open("/dev/urandom", "r", 0)
    if not fd then
        return nil, tostring(err)
    end
    local bytes, read_err = uv.fs_read(fd, 16, 0)
    local closed, close_err = uv.fs_close(fd)
    if not bytes or #bytes ~= 16 or not closed then
        return nil, tostring(read_err or close_err or "short random read")
    end
    return (
        bytes:gsub(".", function(char)
            return string.format("%02x", char:byte())
        end)
    )
end

function M.paths()
    local root = require("sess.storage").root()
    if not root then
        return nil, "session storage is not initialized"
    end
    local dir = root .. "/terminal"
    return {
        root = root,
        dir = dir,
        registry = dir .. "/registry.json",
        socket = dir .. "/tmux.sock",
        config = dir .. "/tmux.conf",
    }
end

-- Existing paths are never chmodded, followed through symlinks, or repaired.
function M.private(path, kind)
    local stat, err, code = uv.fs_lstat(path)
    if not stat then
        return nil, tostring(err), code
    end
    if stat.type ~= kind or stat.uid ~= uv.getuid() or bit.band(stat.mode, 63) ~= 0 then
        return nil, "untrusted terminal " .. kind .. ": " .. path
    end
    return stat
end

function M.owner_key(id)
    return vim.fn.sha256(id and ("owner:" .. id) or "unassigned:"):sub(1, 32)
end

local function fields(value, allowed)
    for key in pairs(value) do
        if not allowed[key] then
            return false
        end
    end
    return true
end

local function validate(data)
    if
        type(data) ~= "table"
        or data.version ~= 1
        or not M.valid_id(data.backend_id)
        or type(data.executions) ~= "table"
        or type(data.owners) ~= "table"
        or not fields(data, { version = true, backend_id = true, owners = true, executions = true })
    then
        return nil, "invalid/incompatible terminal registry"
    end
    for key, owner in pairs(data.owners) do
        if
            not M.valid_id(key)
            or type(owner) ~= "table"
            or not M.valid_id(owner.token)
            or not fields(owner, { owner_id = true, token = true, session_id = true })
            or (owner.owner_id ~= nil and not require("sess.storage").validate_id(owner.owner_id))
            or key ~= M.owner_key(owner.owner_id)
            or (
                owner.session_id ~= nil
                and (type(owner.session_id) ~= "string" or not owner.session_id:match("^%$%d+$"))
            )
        then
            return nil, "invalid terminal owner association"
        end
    end
    for id, record in pairs(data.executions) do
        if
            not M.valid_id(id)
            or type(record) ~= "table"
            or record.id ~= id
            or record.backend_id ~= data.backend_id
            or not M.valid_id(record.token)
            or not M.valid_id(record.owner_key)
            or not data.owners[record.owner_key]
            or record.owner_id ~= data.owners[record.owner_key].owner_id
            or (record.phase ~= "pending" and record.phase ~= "ready")
            or not fields(record, {
                id = true,
                backend_id = true,
                owner_id = true,
                owner_key = true,
                token = true,
                phase = true,
                session_id = true,
                window_id = true,
                pane_id = true,
            })
        then
            return nil, "invalid terminal execution association"
        end
        if
            record.phase == "pending" and (record.session_id or record.window_id or record.pane_id)
        then
            return nil, "invalid pending terminal targets"
        end
        if record.phase == "ready" then
            for field, pattern in pairs({
                session_id = "^%$%d+$",
                window_id = "^@%d+$",
                pane_id = "^%%%d+$",
            }) do
                if type(record[field]) ~= "string" or not record[field]:match(pattern) then
                    return nil, "invalid terminal target"
                end
            end
            if record.session_id ~= data.owners[record.owner_key].session_id then
                return nil, "invalid terminal owning session"
            end
        end
    end
    return data
end

function M.read()
    local paths, err = M.paths()
    if not paths then
        return nil, err
    end
    local root, root_err = M.private(paths.root, "directory")
    if not root then
        return nil, root_err
    end
    local dir, dir_err, code = M.private(paths.dir, "directory")
    if not dir then
        if code == "ENOENT" then
            return nil, nil, paths
        end
        return nil, dir_err
    end
    local stat, stat_err = M.private(paths.registry, "file")
    if not stat then
        return nil, stat_err
    end
    if stat.size > MAX_BYTES then
        return nil, "terminal registry exceeds size limit"
    end
    local fd, open_err = uv.fs_open(paths.registry, "r", 0)
    if not fd then
        return nil, tostring(open_err)
    end
    local content, read_err = uv.fs_read(fd, MAX_BYTES + 1, 0)
    local closed, close_err = uv.fs_close(fd)
    if not content or not closed then
        return nil, tostring(read_err or close_err)
    end
    local ok, data = pcall(vim.json.decode, content)
    if not ok then
        return nil, "corrupt terminal registry: " .. tostring(data)
    end
    local valid, validation_err = validate(data)
    return valid, validation_err, paths
end

function M.write(data)
    local valid, err = validate(data)
    if not valid then
        return false, err
    end
    local paths = M.paths()
    local ok, content = pcall(vim.json.encode, data)
    if not ok or #content > MAX_BYTES then
        return false, "terminal registry cannot be encoded within size limit"
    end
    return M.publish(paths.registry, content, true)
end

-- Publication is atomic. Failed/ambiguous publications are reported, never
-- followed by deletion of execution or association data.
function M.publish(path, content, replace)
    local token, token_err = M.token()
    if not token then
        return false, token_err
    end
    local temporary = path .. ".tmp-" .. token
    local fd, err = uv.fs_open(temporary, "wx", 384)
    if not fd then
        return false, tostring(err)
    end
    local written, write_err = uv.fs_write(fd, content, 0)
    local synced, sync_err = uv.fs_fsync(fd)
    local closed, close_err = uv.fs_close(fd)
    if written ~= #content or not synced or not closed then
        return false,
            "terminal persistence failed (temporary retained): " .. tostring(
                write_err or sync_err or close_err
            )
    end
    local published, publish_err
    if replace then
        published, publish_err = uv.fs_rename(temporary, path)
    else
        published, publish_err = uv.fs_link(temporary, path)
        if published then
            local removed, remove_err = uv.fs_unlink(temporary)
            if not removed then
                return false,
                    "terminal file published but temporary cleanup failed: " .. tostring(remove_err)
            end
        end
    end
    if not published then
        return false, "terminal publication failed (temporary retained): " .. tostring(publish_err)
    end
    return true
end

function M.with_lock(callback, create)
    local paths, err = M.paths()
    if not paths then
        return nil, err
    end
    local trusted, trust_err = M.private(paths.root, "directory")
    if not trusted then
        return nil, trust_err
    end
    local stat, stat_err, code = M.private(paths.dir, "directory")
    if not stat and code == "ENOENT" and create then
        local made, make_err = uv.fs_mkdir(paths.dir, 448)
        if not made then
            return nil, tostring(make_err)
        end
    elseif not stat then
        return nil, stat_err
    end
    local lock = paths.dir .. "/lock"
    local held, lock_err = uv.fs_mkdir(lock, 448)
    if not held then
        return nil, "terminal operation locked (never automatically stolen): " .. tostring(lock_err)
    end
    local called, result, callback_err = pcall(callback, paths)
    local released, release_err = uv.fs_rmdir(lock)
    if not called then
        return nil, tostring(result)
    end
    if not released then
        return nil,
            tostring(callback_err or "terminal operation committed")
                .. "; lock release failed: "
                .. tostring(release_err)
    end
    return result, callback_err
end

function M.initialize(paths)
    local stat, _, code = uv.fs_lstat(paths.registry)
    if stat or code ~= "ENOENT" then
        return M.read()
    end
    -- Only an empty store can be initialized. Missing metadata beside backend
    -- artifacts is an unknown association, not permission to adopt a server.
    local scan = uv.fs_scandir(paths.dir)
    if not scan then
        return nil, "cannot inspect terminal directory"
    end
    while true do
        local name = uv.fs_scandir_next(scan)
        if not name then
            break
        end
        if name ~= "lock" then
            return nil, "terminal registry missing beside existing artifacts"
        end
    end
    local token, err = M.token()
    if not token then
        return nil, err
    end
    local data = { version = 1, backend_id = token, owners = {}, executions = {} }
    local ok, write_err = M.write(data)
    if not ok then
        return nil, write_err
    end
    return data
end

return M
