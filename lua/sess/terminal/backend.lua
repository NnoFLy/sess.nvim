---@class Sess.TerminalExecution
---@field id string
---@field backend_id string
---@field owner_id? string
---@field owner_key string
---@field token string
---@field phase "ready"
---@field session_id string
---@field window_id string
---@field pane_id string

---@class Sess.TerminalAttachment
---@field backend_id string
---@field execution_id string
---@field helper_id string
---@field session_id string
---@field argv string[]
---@field env table<string, string>

local M = {}
local store = require("sess.terminal.storage")
local uv = vim.uv
local TIMEOUT = 3000
local OUTPUT_LIMIT = 65536

local function argv(paths, args)
    local executable = vim.fn.exepath("tmux")
    if executable == "" then
        return nil, "tmux is unavailable"
    end
    local result = { executable, "-S", paths.socket, "-f", paths.config }
    for _, arg in ipairs(args) do
        -- tmux's argv parser treats a trailing semicolon as a command
        -- separator, even in a structured argv. Escape only that syntax.
        result[#result + 1] = arg:gsub(";$", "\\;")
    end
    return result
end

local function run(paths, args, timeout)
    local command, err = argv(paths, args)
    if not command then
        return nil, err
    end
    local chunks, size, exceeded = {}, 0, false
    local process
    local function collect(_, data)
        if not data then
            return
        end
        size = size + #data
        if size > OUTPUT_LIMIT then
            exceeded = true
            if process then
                process:kill(9)
            end
        else
            chunks[#chunks + 1] = data
        end
    end
    local started, object = pcall(vim.system, command, {
        env = { TMUX = "", TMUX_PANE = "" },
        stdout = collect,
        stderr = collect,
    })
    if not started then
        return nil, "tmux subprocess failed: " .. tostring(object)
    end
    process = object
    local result = process:wait(timeout or TIMEOUT)
    local output = table.concat(chunks)
    if exceeded then
        return nil, "tmux output exceeded limit"
    end
    if result.code ~= 0 then
        return nil, "tmux failed (" .. tostring(result.code) .. "): " .. output
    end
    return output
end

local function config(data)
    return table.concat({
        "set-option -s exit-empty off",
        "set-option -s exit-unattached off",
        "set-option -s @sess_backend " .. data.backend_id,
        "set-option -g status off",
        "set-option -g prefix None",
        "set-option -g prefix2 None",
        "set-option -g mouse off",
        "set-option -g destroy-unattached off",
        "set-option -g base-index 0",
        "set-window-option -g remain-on-exit on",
        "set-window-option -g automatic-rename off",
        "unbind-key -a",
        "unbind-key -a -T root",
        "",
    }, "\n")
end

local function server(paths, data, start)
    if #paths.socket > 100 then
        return nil, "terminal socket path exceeds portable tmux limit"
    end
    local stat, _, code = uv.fs_lstat(paths.config)
    if not stat and code == "ENOENT" and start then
        local ok, err = store.publish(paths.config, config(data), false)
        if not ok then
            return nil, err
        end
    else
        local safe, err = store.private(paths.config, "file")
        if not safe or safe.size > 4096 then
            return nil, err or "terminal config exceeds size limit"
        end
        local fd, open_err = uv.fs_open(paths.config, "r", 0)
        if not fd then
            return nil, tostring(open_err)
        end
        local content, read_err = uv.fs_read(fd, 4097, 0)
        local closed, close_err = uv.fs_close(fd)
        if not content or not closed or content ~= config(data) then
            return nil,
                "terminal configuration changed: " .. tostring(
                    read_err or close_err or "content mismatch"
                )
        end
    end
    local socket, _, socket_code = uv.fs_lstat(paths.socket)
    if not socket and socket_code == "ENOENT" and start then
        local started, err = run(paths, { "start-server" })
        if not started then
            return nil, err
        end
        local made = uv.fs_lstat(paths.socket)
        if not made or made.type ~= "socket" or made.uid ~= uv.getuid() then
            return nil, "untrusted terminal socket after startup"
        end
        local changed, change_err = uv.fs_chmod(paths.socket, 384)
        if not changed then
            return nil, tostring(change_err)
        end
    end
    local safe, safe_err = store.private(paths.socket, "socket")
    if not safe then
        return nil, safe_err
    end
    local marker, marker_err = run(paths, { "show-options", "-s", "-v", "@sess_backend" })
    if not marker or vim.trim(marker) ~= data.backend_id then
        return nil, marker_err or "terminal server identity mismatch"
    end
    return true
end

local function option(paths, scope, target, name, value)
    local args = { "set-option" }
    if scope ~= "session" then
        args[#args + 1] = scope
    end
    vim.list_extend(args, { "-t", target, name, value })
    return run(paths, args)
end

local function owner_name(key)
    return "sess_o_" .. key
end

local function owner_valid(paths, data, key, owner)
    if not owner.session_id then
        return nil, "terminal owner session is not committed"
    end
    local output, err = run(paths, {
        "display-message",
        "-p",
        "-t",
        owner.session_id,
        "#{session_id}\t#{session_name}\t#{@sess_backend}\t#{@sess_owner_token}",
    })
    if not output then
        return nil, err
    end
    local expected =
        table.concat({ owner.session_id, owner_name(key), data.backend_id, owner.token }, "\t")
    if output:gsub("\n$", "") ~= expected then
        return nil, "terminal owner identity mismatch"
    end
    return true
end

local function verified(paths, data, record)
    if not record then
        return nil, "terminal execution does not exist"
    end
    if record.phase ~= "ready" then
        return nil, "terminal creation is incomplete; association preserved"
    end
    local owner = data.owners[record.owner_key]
    local valid, err = owner_valid(paths, data, record.owner_key, owner)
    if not valid then
        return nil, err
    end
    local output, lookup_err = run(paths, {
        "display-message",
        "-p",
        "-t",
        record.session_id .. ":" .. record.window_id .. "." .. record.pane_id,
        "#{session_id}\t#{window_id}\t#{pane_id}\t#{window_panes}\t#{@sess_execution}\t#{@sess_window_token}\t#{@sess_pane_token}",
    })
    if not output then
        return nil, lookup_err
    end
    local expected = table.concat({
        record.session_id,
        record.window_id,
        record.pane_id,
        "1",
        record.id,
        record.token,
        record.token,
    }, "\t")
    if output:gsub("\n$", "") ~= expected then
        return nil, "terminal execution identity mismatch (stale or reused target)"
    end
    return vim.deepcopy(record)
end

local function input(opts)
    if type(opts) ~= "table" then
        return nil, "terminal options must be a table"
    end
    if opts.owner_id ~= nil then
        local valid, err = require("sess.storage").validate_id(opts.owner_id)
        if not valid then
            return nil, err
        end
    end
    local cwd_stat = require("sess.path").is_absolute(opts.cwd) and uv.fs_stat(opts.cwd)
    if not cwd_stat or cwd_stat.type ~= "directory" then
        return nil, "terminal cwd must be an existing absolute directory"
    end
    if
        opts.command ~= nil
        and (type(opts.command) ~= "string" or opts.command:find("%z") or #opts.command > 32768)
    then
        return nil, "terminal command must be a NUL-free string within 32768 bytes"
    end
    local shell = opts.shell or vim.o.shell
    if type(shell) ~= "string" or shell == "" or shell:find("%z") then
        return nil, "terminal shell must name one executable, not shell arguments"
    end
    shell = vim.fn.exepath(shell)
    if shell == "" or vim.fn.executable(shell) ~= 1 then
        return nil, "terminal shell executable is unavailable"
    end
    return shell
end

-- Returns Execution?, error?. Launch text is never stored. A failed operation
-- may leave a pending association/live execution; it is never silently retried.
---@param opts {owner_id?: string, cwd: string, command?: string, shell?: string}
---@return Sess.TerminalExecution?, string?
function M.create(opts)
    local shell, err = input(opts)
    if not shell then
        return nil, err
    end
    return store.with_lock(function(paths)
        local data, read_err = store.initialize(paths)
        if not data then
            return nil, read_err
        end
        local ready, server_err = server(paths, data, true)
        if not ready then
            return nil, server_err
        end
        local id, id_err = store.token()
        local token, token_err = store.token()
        if not id or not token then
            return nil, id_err or token_err
        end
        local key = store.owner_key(opts.owner_id)
        local owner = data.owners[key]
        if owner then
            local valid, owner_err = owner_valid(paths, data, key, owner)
            if not valid then
                return nil, owner_err
            end
        else
            local owner_token, random_err = store.token()
            if not owner_token then
                return nil, random_err
            end
            owner = { owner_id = opts.owner_id, token = owner_token }
            data.owners[key] = owner
        end
        local record = {
            id = id,
            backend_id = data.backend_id,
            owner_id = opts.owner_id,
            owner_key = key,
            token = token,
            phase = "pending",
        }
        data.executions[id] = record
        local saved, save_err = store.write(data)
        if not saved then
            return nil, save_err
        end
        local args
        -- tmux expands formats in -c; doubling # keeps the path literal.
        local cwd = opts.cwd:gsub("#", "##")
        if owner.session_id then
            args = {
                "new-window",
                "-d",
                "-P",
                "-F",
                "#{session_id}\t#{window_id}\t#{pane_id}",
                "-t",
                owner.session_id .. ":",
                "-n",
                "execution",
                "-c",
                cwd,
            }
        else
            args = {
                "new-session",
                "-d",
                "-P",
                "-F",
                "#{session_id}\t#{window_id}\t#{pane_id}",
                "-s",
                owner_name(key),
                "-n",
                "execution",
                "-c",
                cwd,
            }
        end
        vim.list_extend(args, { "--", shell, opts.command ~= nil and "-c" or "-i" })
        if opts.command ~= nil then
            args[#args + 1] = opts.command
        end
        local output, launch_err = run(paths, args)
        if not output then
            return nil,
                "terminal launch failed; pending association retained: " .. tostring(launch_err)
        end
        local sid, wid, pid = output:match("^(%$%d+)\t(@%d+)\t(%%%d+)\n$")
        if not sid then
            return nil, "terminal launch returned invalid targets; association retained"
        end
        owner.session_id = sid
        local operations = {
            { "session", sid, "@sess_backend", data.backend_id },
            { "session", sid, "@sess_owner_token", owner.token },
            { "-w", wid, "@sess_execution", id },
            { "-w", wid, "@sess_window_token", token },
            { "-p", pid, "@sess_pane_token", token },
        }
        for _, operation in ipairs(operations) do
            local marked, mark_err = option(paths, unpack(operation))
            if not marked then
                return nil,
                    "terminal identity publication failed; association retained: " .. tostring(
                        mark_err
                    )
            end
        end
        record.session_id, record.window_id, record.pane_id, record.phase = sid, wid, pid, "ready"
        saved, save_err = store.write(data)
        if not saved then
            return nil,
                "terminal launched but persistence failed; pending association retained: "
                    .. tostring(save_err)
        end
        return verified(paths, data, record)
    end, true)
end

---@param id string
---@return Sess.TerminalExecution?, string?
function M.get(id)
    if not store.valid_id(id) then
        return nil, "invalid terminal execution id"
    end
    local data, err, paths = store.read()
    if not data then
        return nil, err or "terminal execution does not exist"
    end
    local record = data.executions[id]
    if not record then
        return nil, "terminal execution does not exist"
    end
    local ready, server_err = server(paths, data, false)
    if not ready then
        return nil, server_err
    end
    return verified(paths, data, record)
end

-- Conservative deletion gate: missing/stale references and unregistered work
-- are uncertainty, not evidence that it is safe to orphan a session's work.
---@param owner_id string
---@return boolean, string?
function M.can_delete_owner(owner_id)
    local valid, validation_err = require("sess.storage").validate_id(owner_id)
    if not valid then
        return false, validation_err
    end
    local data, err, paths = store.read()
    if not data then
        return err == nil, err
    end
    local result, check_err = store.with_lock(function()
        data, err = store.read()
        if not data then
            return nil, err or "terminal registry disappeared"
        end
        if not data.owners[store.owner_key(owner_id)] then
            return true
        end
        for _, record in pairs(data.executions) do
            if record.owner_id == owner_id then
                return nil,
                    "session owns persistent terminals (or incomplete associations); deletion refused"
            end
        end
        local ready, server_err = server(paths, data, false)
        if not ready then
            return nil, server_err
        end
        local inventory, inventory_err = run(paths, {
            "list-panes",
            "-a",
            "-F",
            "#{session_id}\t#{window_id}\t#{pane_id}\t#{@sess_execution}\t#{@sess_window_token}\t#{@sess_pane_token}",
        })
        if not inventory then
            return nil, inventory_err
        end
        for line in inventory:gmatch("[^\n]+") do
            local sid, wid, pid, id, window_token, pane_token =
                line:match("^(%$%d+)\t(@%d+)\t(%%%d+)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
            local record = id and data.executions[id]
            if
                not record
                or record.phase ~= "ready"
                or record.window_id ~= wid
                or record.pane_id ~= pid
                or record.token ~= window_token
                or record.token ~= pane_token
            then
                return nil, "unknown/corrupt live terminal association; deletion refused"
            end
            local checked, verify_err = verified(paths, data, record)
            if not checked then
                return nil, verify_err
            end
            -- A link in a helper is harmless; the original owner is verified above.
            if sid == record.session_id and record.owner_id == owner_id then
                return nil, "session owns persistent terminals; deletion refused"
            end
        end
        return true
    end)
    return result == true, check_err
end

local function helper_valid(paths, data, attachment)
    if
        type(attachment) ~= "table"
        or not store.valid_id(attachment.helper_id)
        or not store.valid_id(attachment.execution_id)
        or attachment.backend_id ~= data.backend_id
        or type(attachment.session_id) ~= "string"
        or not attachment.session_id:match("^%$%d+$")
    then
        return nil, "invalid terminal attachment identity"
    end
    local output, err = run(paths, {
        "display-message",
        "-p",
        "-t",
        attachment.session_id,
        "#{session_id}\t#{session_name}\t#{@sess_backend}\t#{@sess_helper}\t#{session_windows}\t#{window_id}",
    })
    local record = data.executions[attachment.execution_id]
    if not record or record.phase ~= "ready" then
        return nil, "attachment execution is unknown or incomplete"
    end
    local expected = table.concat({
        attachment.session_id,
        "sess_h_" .. attachment.helper_id,
        data.backend_id,
        attachment.helper_id,
        "1",
        record.window_id,
    }, "\t") .. "\n"
    if not output or output ~= expected then
        return nil, err or "terminal helper identity mismatch"
    end
    return true
end

-- Returns Attachment?, error?. Pass argv and env to jobstart/termopen; only
-- prepare_attachment launches a helper, and neither method relaunches work.
---@param id string
---@return Sess.TerminalAttachment?, string?
function M.prepare_attachment(id)
    local execution, err = M.get(id)
    if not execution then
        return nil, err
    end
    local placeholder = vim.fn.exepath("true")
    if placeholder == "" then
        return nil, "attachment placeholder executable 'true' is unavailable"
    end
    return store.with_lock(function(paths)
        local data, read_err = store.read()
        if not data then
            return nil, read_err
        end
        local ready, server_err = server(paths, data, false)
        if not ready then
            return nil, server_err
        end
        local checked, check_err = verified(paths, data, data.executions[id])
        if not checked then
            return nil, check_err
        end
        local token, token_err = store.token()
        if not token then
            return nil, token_err
        end
        local name = "sess_h_" .. token
        local output, create_err = run(paths, {
            "new-session",
            "-d",
            "-P",
            "-F",
            "#{session_id}\t#{window_id}",
            "-s",
            name,
            "--",
            placeholder,
            "--",
        })
        if not output then
            return nil, create_err
        end
        local sid, wid = output:match("^(%$%d+)\t(@%d+)\n$")
        if not sid then
            return nil, "invalid helper targets; helper retained"
        end
        local marked, mark_err = option(paths, "session", sid, "@sess_backend", data.backend_id)
        if marked then
            marked, mark_err = option(paths, "session", sid, "@sess_helper", token)
        end
        if not marked then
            return nil, "helper retained after marker failure: " .. tostring(mark_err)
        end
        local linked, link_err =
            run(paths, { "link-window", "-s", execution.window_id, "-t", sid .. ":1" })
        if not linked then
            return nil, "helper retained after link failure: " .. tostring(link_err)
        end
        -- Verify both placeholder and helper identities before removing the
        -- placeholder; never kill a discovered or reused target by name.
        local prefix = table.concat({ sid, name, token, wid }, "\t") .. "\t"
        local check, placeholder_err
        local deadline = uv.hrtime() / 1e6 + TIMEOUT
        -- new-session returning does not mean its short-lived placeholder has
        -- exited yet. Poll only this exact identity, under one total deadline.
        vim.wait(TIMEOUT, function()
            local remaining = math.floor(deadline - uv.hrtime() / 1e6)
            if remaining <= 0 then
                placeholder_err = "helper placeholder exit timed out; retained"
                return true
            end
            check, placeholder_err = run(paths, {
                "display-message",
                "-p",
                "-t",
                sid .. ":" .. wid,
                "#{session_id}\t#{session_name}\t#{@sess_helper}\t#{window_id}\t#{pane_dead}",
            }, remaining)
            if not check or check == prefix .. "1\n" then
                return true
            end
            if check ~= prefix .. "0\n" then
                placeholder_err = "helper placeholder identity mismatch; retained"
                return true
            end
            return false
        end, 20)
        if placeholder_err or check ~= prefix .. "1\n" then
            return nil, placeholder_err or "helper placeholder exit timed out; retained"
        end
        local removed, remove_err = run(paths, { "unlink-window", "-k", "-t", sid .. ":" .. wid })
        if not removed then
            return nil, "helper placeholder cleanup failed: " .. tostring(remove_err)
        end
        local attachment =
            { backend_id = data.backend_id, execution_id = id, helper_id = token, session_id = sid }
        local safe, safe_err = helper_valid(paths, data, attachment)
        if not safe then
            return nil, safe_err
        end
        local command, command_err = argv(paths, { "attach-session", "-t", "=" .. name })
        if not command then
            return nil, command_err
        end
        attachment.argv = command
        attachment.env = { TMUX = "", TMUX_PANE = "" }
        return attachment
    end)
end

-- Kills only the verified helper session, not its linked execution window.
---@param attachment Sess.TerminalAttachment
---@return boolean, string?
function M.cleanup_attachment(attachment)
    local result, err = store.with_lock(function(paths)
        local data, read_err = store.read()
        if not data then
            return nil, read_err
        end
        local ready, server_err = server(paths, data, false)
        if not ready then
            return nil, server_err
        end
        local valid, validation_err = helper_valid(paths, data, attachment)
        if not valid then
            return nil, validation_err
        end
        local execution, execution_err =
            verified(paths, data, data.executions[attachment.execution_id])
        if not execution then
            return nil,
                "refusing helper cleanup without verified owning window: " .. tostring(
                    execution_err
                )
        end
        return run(paths, { "kill-session", "-t", "=sess_h_" .. attachment.helper_id })
    end)
    return result ~= nil, err
end

return M
