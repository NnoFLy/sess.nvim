local state = require("sess.state")
local default_process = require("sess.agent.process_probe")
local default_terminal = require("sess.agent.terminal_probe")
local default_status = require("sess.agent.status")

local M = {}

local function session_buffers(session_id)
    local result, seen = {}, {}
    local function add(bufnr)
        if not seen[bufnr] then
            seen[bufnr] = true
            result[#result + 1] = bufnr
        end
    end

    if state.is_current_session(session_id) then
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local ok, bufnr = pcall(vim.api.nvim_win_get_buf, win)
            if ok then add(bufnr) end
        end
    end
    for _, bufnr in ipairs(state.get_view_buffers(session_id)) do add(bufnr) end
    table.sort(result)
    return result
end

local function now_ms()
    local uv = vim.uv or vim.loop
    if uv and uv.hrtime then return uv.hrtime() / 1000000 end
    return os.clock() * 1000
end

local IDENTITY_CACHE_TTL = 5000
local MAX_DIAGNOSTIC_LENGTH = 240
local MAX_SNAPSHOT_LINES = 200
local MAX_SNAPSHOT_LINE_LENGTH = 1000
local MAX_SNAPSHOT_TOTAL_BYTES = 65536
local MAX_OBSERVATION_DIAGNOSTICS = 64
local MAX_OBSERVATION_EVIDENCE = 32
local MAX_OBSERVATION_EVIDENCE_LENGTH = 240
local MAX_OBSERVATION_FIELD_LENGTH = 240

local function diagnostic(value)
    value = tostring(value or "unknown probe failure")
    if #value > MAX_DIAGNOSTIC_LENGTH then value = value:sub(1, MAX_DIAGNOSTIC_LENGTH) end
    return value
end

local function add_diagnostic(result, message)
    result = result or {}
    result[#result + 1] = diagnostic(message)
    return result
end

local function valid_terminal(bufnr)
    local ok, valid = pcall(vim.api.nvim_buf_is_valid, bufnr)
    if not ok or not valid then return false end
    local type_ok, buftype = pcall(function() return vim.bo[bufnr].buftype end)
    return type_ok and buftype == "terminal"
end

local function call(probe, name, ...)
    if type(probe) ~= "table" or type(probe[name]) ~= "function" then
        return false, name .. " probe is unavailable"
    end
    local ok, value, extra = pcall(probe[name], ...)
    if not ok then return false, value end
    return true, value, extra
end

local snapshot_fields = {
    bottom_lines = "table",
    recent_lines = "table",
    current_prompt_lines = "table",
    before_current_prompt_lines = "table",
    top_lines = "table",
    bufnr = "number",
    changedtick = "number",
    osc_title = "string",
    complete = "boolean",
    error = "string",
}

local function validate_snapshot(value)
    if type(value) ~= "table" then return false, "terminal snapshot probe returned an invalid result" end
    for field, expected in pairs(snapshot_fields) do
        if value[field] ~= nil and type(value[field]) ~= expected then
            return false, "terminal snapshot " .. field .. " must be a " .. expected
        end
        if (field == "osc_title" or field == "error")
            and type(value[field]) == "string"
            and #value[field] > MAX_SNAPSHOT_LINE_LENGTH
        then
            return false, "terminal snapshot " .. field .. " is too long"
        end
    end
    if value.bufnr ~= nil and (value.bufnr % 1 ~= 0 or value.bufnr < 1) then
        return false, "terminal snapshot bufnr must be a positive integer"
    end
    if value.changedtick ~= nil and (value.changedtick % 1 ~= 0 or value.changedtick < 0) then
        return false, "terminal snapshot changedtick must be a non-negative integer"
    end
    if value.complete ~= true then
        return false, "terminal snapshot must explicitly be complete"
    end
    local total_bytes = 0
    for field, expected in pairs(snapshot_fields) do
        if expected == "table" and value[field] ~= nil then
            local count = 0
            for index, line in pairs(value[field]) do
                count = count + 1
                if count > MAX_SNAPSHOT_LINES then
                    return false, "terminal snapshot " .. field .. " has too many lines"
                end
                if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > MAX_SNAPSHOT_LINES then
                    return false, "terminal snapshot " .. field .. " has an invalid line index"
                end
                if type(line) ~= "string" then
                    return false, "terminal snapshot " .. field .. "[" .. index .. "] must be a string"
                end
                if #line > MAX_SNAPSHOT_LINE_LENGTH then
                    return false, "terminal snapshot " .. field .. "[" .. index .. "] is too long"
                end
                total_bytes = total_bytes + #line
                if total_bytes > MAX_SNAPSHOT_TOTAL_BYTES then
                    return false, "terminal snapshot is too large"
                end
            end
            if count ~= #value[field] then
                return false, "terminal snapshot " .. field .. " has an invalid line list"
            end
        end
    end
    return true
end

local observation_fields = {
    state = true,
    source = true,
    authority = true,
    rule_id = true,
    rule_priority = true,
    rule_region = true,
    manifest_id = true,
    manifest_version = true,
    evidence = true,
    skip_state_update = true,
    diagnostics = true,
    stale = true,
    probe_failed = true,
}

local function validate_observation(value)
    if type(value) ~= "table" or type(value.state) ~= "string" then
        return false, "status observation returned an invalid result"
    end
    for key in pairs(value) do
        if not observation_fields[key] then
            return false, "status observation contains an invalid field: " .. tostring(key)
        end
    end
    for _, field in ipairs({ "source", "authority", "rule_id", "rule_region", "manifest_id" }) do
        if value[field] ~= nil then
            if type(value[field]) ~= "string" then
                return false, "status observation " .. field .. " must be a string"
            end
            if #value[field] == 0 or #value[field] > MAX_OBSERVATION_FIELD_LENGTH then
                return false, "status observation " .. field .. " is invalid or too long"
            end
        end
    end
    if #value.state == 0 or #value.state > MAX_OBSERVATION_FIELD_LENGTH then
        return false, "status observation state is invalid or too long"
    end
    for _, field in ipairs({ "manifest_version", "rule_priority" }) do
        if value[field] ~= nil and (type(value[field]) ~= "number" or value[field] % 1 ~= 0) then
            return false, "status observation " .. field .. " must be an integer"
        end
    end
    for _, specification in ipairs({
        { "diagnostics", MAX_OBSERVATION_DIAGNOSTICS, MAX_DIAGNOSTIC_LENGTH },
        { "evidence", MAX_OBSERVATION_EVIDENCE, MAX_OBSERVATION_EVIDENCE_LENGTH },
    }) do
        local field, limit, length = specification[1], specification[2], specification[3]
        local values = value[field]
        if values ~= nil then
            if type(values) ~= "table" then return false, "status observation " .. field .. " must be a table" end
            local count, total_bytes = 0, 0
            for index, item in pairs(values) do
                count = count + 1
                if count > limit then return false, "status observation " .. field .. " is too large" end
                if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > limit then
                    return false, "status observation " .. field .. " has an invalid index"
                end
                if type(item) ~= "string" then
                    return false, "status observation " .. field .. " must contain strings"
                end
                if #item > length then return false, "status observation " .. field .. " contains a value that is too long" end
                total_bytes = total_bytes + #item
                if total_bytes > limit * length then
                    return false, "status observation " .. field .. " is too large"
                end
            end
            if count ~= #values then return false, "status observation " .. field .. " has an invalid list" end
        end
    end
    if value.skip_state_update ~= nil and type(value.skip_state_update) ~= "boolean" then
        return false, "status observation skip_state_update must be a boolean"
    end
    if value.probe_failed ~= nil and type(value.probe_failed) ~= "boolean" then
        return false, "status observation probe_failed must be a boolean"
    end
    if value.stale ~= nil and type(value.stale) ~= "boolean" then
        return false, "status observation stale must be a boolean"
    end
    return true
end

local function copy_observation(value)
    if type(value) ~= "table" then return nil end
    local result = {}
    for key in pairs(observation_fields) do
        local item = value[key]
        if item ~= nil then
            result[key] = type(item) == "table" and vim.deepcopy(item) or item
        end
    end
    result.diagnostics = vim.deepcopy(value.diagnostics or {})
    return result
end

local function is_valid_observation(value)
    return type(value) == "table"
        and type(value.state) == "string"
        and value.state ~= "unknown"
        and value.source ~= "unknown"
        and value.probe_failed ~= true
end

local function is_screen_observation(value)
    return is_valid_observation(value)
        and (value.source == "screen" or value.source == "fallback")
end

local function fresh_integration(value, now)
    if type(value) ~= "table" then return nil, false end
    local state_value = value.state or value.status
    if type(state_value) ~= "string" or state_value == "" or #state_value > MAX_OBSERVATION_FIELD_LENGTH then
        return nil, false
    end
    -- `unknown` is useful as an identity/status diagnostic but cannot claim
    -- lifecycle authority over a usable screen observation.
    if state_value == "unknown" and value.manual ~= true then
        return copy_observation(value), false
    end

    if value.diagnostics ~= nil then
        if type(value.diagnostics) ~= "table" then return nil, false end
        local count = 0
        for index, message in pairs(value.diagnostics) do
            count = count + 1
            if count > MAX_OBSERVATION_DIAGNOSTICS
                or type(index) ~= "number"
                or index % 1 ~= 0
                or index < 1
                or index > MAX_OBSERVATION_DIAGNOSTICS
                or type(message) ~= "string"
                or #message > MAX_DIAGNOSTIC_LENGTH
            then
                return nil, false
            end
        end
        if count ~= #value.diagnostics then return nil, false end
    end

    if value.released == true then return value, false end
    local deadline = value.expires_at or value.fresh_until or value.deadline
    if deadline ~= nil and type(deadline) ~= "number" then return nil, false end
    if deadline and deadline <= now then return value, false end
    local result = copy_observation(value) or {}
    result.state = state_value
    result.source = "integration"
    result.authority = value.manual == true and "manual" or "lifecycle"
    result.stale = false
    result.diagnostics = result.diagnostics or {}
    return result, true
end

function M.new(probes)
    probes = probes or {}
    local process = probes.process or default_process
    local terminal = probes.terminal or default_terminal
    local status = probes.status or default_status
    local identity_cache = {}
    local status_cache = {}
    local previous_observation = {}

    local function discover(bufnr, use_cache)
        local identity_diagnostics = {}
        local identity_probe_failed = false
        local job_ok, job_id = call(terminal, "job_id", bufnr)
        if not job_ok then
            local job_error = job_id
            job_id = nil
            identity_probe_failed = true
            add_diagnostic(identity_diagnostics, "terminal job probe failed: " .. diagnostic(job_error))
        end
        local name_ok, terminal_name = call(terminal, "name", bufnr)
        if not name_ok then
            terminal_name = nil
            identity_probe_failed = true
            add_diagnostic(identity_diagnostics, "terminal name probe failed")
        end

        local cached = identity_cache[bufnr]
        local now = now_ms()
        if use_cache
            and cached
            and cached.job_id == job_id
            and cached.terminal_name == terminal_name
            and cached.expires_at > now
        then
            return cached.agent, cached, true
        end

        -- A new job is a new identity, even when the terminal buffer was
        -- reused. Never carry screen observations across that boundary.
        if cached and ((job_ok and cached.job_id ~= job_id)
            or (name_ok and cached.terminal_name ~= terminal_name)) then
            status_cache[bufnr] = nil
            previous_observation[bufnr] = nil
        end

        if type(terminal.job_alive) == "function" then
            local alive_ok, alive = pcall(terminal.job_alive, bufnr)
            if not alive_ok or alive ~= true then
                identity_cache[bufnr] = nil
                status_cache[bufnr] = nil
                previous_observation[bufnr] = nil
                return nil, {
                    job_id = job_id,
                    terminal_name = terminal_name,
                    diagnostics = { "terminal job is no longer running" },
                }, false
            end
        end

        local agent
        local identity_source = "unknown"
        local agent_ok, value, job_diagnostic = call(process, "job_agent", job_id)
        if agent_ok then
            agent = value
            if job_diagnostic then add_diagnostic(identity_diagnostics, job_diagnostic) end
            if agent then identity_source = "job-process-tree" end
        else
            identity_probe_failed = true
            add_diagnostic(identity_diagnostics, "job identity probe failed: " .. diagnostic(value))
        end
        if not agent and terminal_name then
            local command_ok, command_agent, command_diagnostic = call(process, "command_agent", terminal_name)
            if command_ok then
                agent = command_agent
                if command_diagnostic then add_diagnostic(identity_diagnostics, command_diagnostic) end
                if agent then identity_source = "terminal-name" end
            else
                identity_probe_failed = true
                add_diagnostic(identity_diagnostics, "terminal command identity probe failed: " .. diagnostic(command_agent))
            end
        end

        -- A transient identity failure must not make a known live terminal
        -- disappear. Do not retain an identity across an explicit job/name
        -- change, but keep the prior agent when the same target is still live.
        if not agent
            and identity_probe_failed
            and cached
            and cached.agent
            and cached.job_id == job_id
            and (not name_ok or cached.terminal_name == terminal_name)
        then
            agent = cached.agent
            identity_source = cached.identity and cached.identity.source or "unknown"
            add_diagnostic(identity_diagnostics, "retained previous agent identity after probe failure")
        end

        local pid
        if type(job_id) == "number" then
            local pid_ok, value = pcall(vim.fn.jobpid, job_id)
            if pid_ok and type(value) == "number" and value > 0 then pid = value end
        end
        local entry = {
            job_id = job_id,
            terminal_name = terminal_name,
            agent = agent,
            identity = {
                source = identity_source,
                command = terminal_name or agent,
                pid = pid,
            },
            diagnostics = identity_diagnostics,
            probe_failed = identity_probe_failed,
            expires_at = now + IDENTITY_CACHE_TTL,
        }
        identity_cache[bufnr] = entry
        return agent, entry, false
    end

    local function snapshot(bufnr)
        if type(terminal.snapshot) == "function" then
            local ok, value = call(terminal, "snapshot", bufnr)
            if not ok then
                return nil, { "terminal snapshot probe failed: " .. diagnostic(value) }
            end
            local valid, validation_error = validate_snapshot(value)
            if not valid then
                return value, { validation_error }
            end
            if value.complete == false then
                local message = value.error and (": " .. diagnostic(value.error)) or ""
                return value, { "terminal snapshot incomplete" .. message }
            end
            return value, {}
        end

        -- Keep compatibility with injected probes implementing only the old
        -- flat-lines API. The built-in probe always supplies snapshot().
        local ok, lines = call(terminal, "lines", bufnr)
        if not ok then return nil, { "terminal lines probe failed: " .. diagnostic(lines) } end
        if type(lines) ~= "table" then return nil, { "terminal lines probe returned an invalid result" } end
        local total_bytes = 0
        local count = 0
        for index, line in pairs(lines) do
            count = count + 1
            if count > MAX_SNAPSHOT_LINES then
                return nil, { "terminal lines probe returned too many lines" }
            end
            if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > MAX_SNAPSHOT_LINES then
                return nil, { "terminal lines probe returned an invalid line index" }
            end
            if type(line) ~= "string" then
                return nil, { "terminal lines probe line " .. index .. " must be a string" }
            end
            if #line > MAX_SNAPSHOT_LINE_LENGTH then
                return nil, { "terminal lines probe returned an overlong line" }
            end
            total_bytes = total_bytes + #line
            if total_bytes > MAX_SNAPSHOT_TOTAL_BYTES then
                return nil, { "terminal lines probe returned too much data" }
            end
        end
        if count ~= #lines then
            return nil, { "terminal lines probe returned an invalid line list" }
        end
        return {
            bufnr = bufnr,
            changedtick = nil,
            bottom_lines = lines,
            recent_lines = lines,
            current_prompt_lines = lines,
            top_lines = lines,
            complete = true,
        }, {}
    end

    local function screen_observation(name, screen, probe_diagnostics)
        if #probe_diagnostics > 0 then return nil end
        local observe = status.observe
        if type(observe) == "function" then
            local ok, result = pcall(observe, { name = name, screen = screen })
            if not ok then
                return nil, { "status observation failed: " .. diagnostic(result) }
            end
            local valid, validation_error = validate_observation(result)
            if not valid then
                return nil, { validation_error }
            end

            return result, {}
        end

        local lines = screen and (screen.bottom_lines or screen.recent_lines)
        local ok, result = pcall(status.classify, lines, name)
        if not ok or type(result) ~= "string" then
            return nil, { "status classifier failed: " .. diagnostic(result) }
        end
        return { state = result, source = result == "unknown" and "unknown" or "screen", diagnostics = {} }, {}
    end

    local function arbitrate(bufnr, name, screen_result, probe_diagnostics, options)
        local previous = previous_observation[bufnr]
        local integration, integration_fresh = fresh_integration(options and options.integration, now_ms())
        local result = screen_result and copy_observation(screen_result) or nil
        local observation_failed = #probe_diagnostics > 0 or (result and result.probe_failed == true) or false
        local diagnostics = {}
        for _, message in ipairs(probe_diagnostics or {}) do diagnostics[#diagnostics + 1] = message end
        if result then
            for _, message in ipairs(result.diagnostics or {}) do diagnostics[#diagnostics + 1] = message end
        end
        if integration_fresh then
            -- A current high-confidence approval prompt is safer than a
            -- non-blocking integration state. The integration still wins for
            -- blocked, and ordinary screen text never overrides it.
            if integration.authority == "lifecycle"
                and integration.state ~= "blocked"
                and result
                and result.state == "blocked"
                and result.rule_priority
                and result.rule_priority >= 100
                and result.rule_region == "current_prompt"
            then
                result.authority = "derived"
                result.diagnostics = diagnostics
                result.diagnostics[#result.diagnostics + 1] =
                    "high-confidence screen blocker overrides integration status"
                return result
            end
            integration.diagnostics = diagnostics
            return integration
        end

        -- A result explicitly marked as failed is not usable even when it
        -- contains a state. Treat it like a failed snapshot so it cannot
        -- become the last-good observation or a successful cache entry.
        if observation_failed then result = nil end

        if result and result.skip_state_update then
            if previous and is_valid_observation(previous) then
                local retained = copy_observation(previous)
                retained.source = "stale"
                retained.authority = "retained"
                retained.stale = true
                retained.probe_failed = true
                retained.diagnostics = diagnostics
                retained.diagnostics[#retained.diagnostics + 1] = "screen observation skipped state update"
                return retained
            end
            return {
                state = "unknown", source = "unknown", authority = "none",
                stale = true, probe_failed = true,
                diagnostics = { "screen observation skipped state update; no prior status" },
            }
        end

        if result and is_valid_observation(result) then
            result.authority = result.authority or "derived"
            result.diagnostics = diagnostics
            if integration then
                result.diagnostics[#result.diagnostics + 1] = "integration status is stale; screen observation used"
            end
            return result
        end

        if integration then
            diagnostics[#diagnostics + 1] = "integration status is stale; it was not retained"
        end

        -- A complete snapshot with no matching rule is a trustworthy
        -- unknown/default result and must not be hidden by an old status.
        -- Retention is only for an actual probe/observation failure.
        if previous and is_valid_observation(previous) and observation_failed then
            local retained = copy_observation(previous)
            retained.source = "stale"
            retained.authority = "retained"
            retained.stale = true
            retained.probe_failed = true
            retained.diagnostics = diagnostics
            retained.diagnostics[#retained.diagnostics + 1] = "retained previous status after probe failure"
            return retained
        end

        local unknown = result or { state = "unknown", source = "unknown" }
        unknown.state = type(unknown.state) == "string" and unknown.state or "unknown"
        unknown.source = unknown.source or "unknown"
        unknown.authority = "none"
        unknown.probe_failed = observation_failed
        unknown.diagnostics = diagnostics
        if #unknown.diagnostics == 0 then unknown.diagnostics[1] = "status observation unavailable" end
        return unknown
    end

    local function changedtick(bufnr)
        if type(terminal.changedtick) ~= "function" then return nil, {} end
        local ok, value = call(terminal, "changedtick", bufnr)
        if not ok then return nil, { "terminal changedtick probe failed: " .. diagnostic(value) } end
        if type(value) ~= "number" or value ~= value or value % 1 ~= 0 or value < 0 then
            return nil, { "terminal changedtick probe returned an invalid revision" }
        end
        return value, {}
    end

    local function classify(bufnr, name, identity, use_cache, options)
        local tick, tick_diagnostics = changedtick(bufnr)
        local job_id = identity and identity.job_id
        local cached = status_cache[bufnr]
        if use_cache
            and not (options and options.integration)
            and tick ~= nil
            and cached
            and cached.name == name
            and cached.job_id == job_id
            and cached.changedtick == tick
        then
            return cached.value, cached.screen, true
        end

        local screen, snapshot_diagnostics = snapshot(bufnr)
        local probe_diagnostics = {}
        for _, message in ipairs(tick_diagnostics) do probe_diagnostics[#probe_diagnostics + 1] = message end
        for _, message in ipairs(snapshot_diagnostics) do probe_diagnostics[#probe_diagnostics + 1] = message end
        local screen_result, status_diagnostics = screen_observation(name, screen, probe_diagnostics)
        for _, message in ipairs(status_diagnostics or {}) do probe_diagnostics[#probe_diagnostics + 1] = message end
        local value = arbitrate(bufnr, name, screen_result, probe_diagnostics, options)

        -- Integration observations are authoritative for this call only. They
        -- must never become the last-good screen observation, since doing so
        -- would make a later failed screen probe report integration state as
        -- stale screen data.
        if is_screen_observation(value) and not value.stale and not value.skip_state_update then
            previous_observation[bufnr] = copy_observation(value)
        elseif screen_result and not screen_result.skip_state_update and not value.probe_failed
            and value.source ~= "integration" then
            previous_observation[bufnr] = nil
        end
        local screen_summary = {
            changedtick = type(screen) == "table" and screen.changedtick or tick,
            line_count = type(screen) == "table" and type(screen.recent_lines) == "table" and #screen.recent_lines or 0,
            complete = type(screen) == "table" and screen.complete == true and #snapshot_diagnostics == 0,
            error = type(screen) == "table" and screen.error or nil,
        }
        local effective_tick = screen and screen.changedtick or tick
        if tick ~= nil and not value.stale and not value.probe_failed and value.source ~= "integration"
            and not (options and options.integration)
        then
            status_cache[bufnr] = {
                name = name,
                job_id = job_id,
                changedtick = effective_tick,
                value = value,
                screen = screen_summary,
            }
        else
            status_cache[bufnr] = nil
        end
        return value, screen_summary, false
    end

    local function row(bufnr, agent, identity, options)
        local observation = classify(bufnr, agent, identity, options and options.cache == true, options)
        local result = {
            id = "terminal:" .. bufnr,
            name = agent,
            status = observation.state,
            source = observation.source,
            authority = observation.authority,
            stale = observation.stale == true,
            target = { bufnr = bufnr },
        }
        local diagnostics = {}
        for _, message in ipairs(identity.diagnostics or {}) do diagnostics[#diagnostics + 1] = message end
        for _, message in ipairs(observation.diagnostics or {}) do diagnostics[#diagnostics + 1] = message end
        if observation.probe_failed or identity.probe_failed then result.probe_failed = true end
        if #diagnostics > 0 then result.diagnostics = diagnostics end
        return result
    end

    local function explain(bufnr, name, options)
        options = options or {}
        if not valid_terminal(bufnr) then
            return nil, { "terminal target is unavailable or its job is no longer running" }
        end
        local agent, identity, identity_cached = discover(bufnr, true)
        if not agent then
            local diagnostics = vim.deepcopy(identity and identity.diagnostics or {})
            if #diagnostics == 0 then diagnostics[1] = "agent identity unavailable" end
            -- Registered agents already provide a trusted bounded manifest
            -- name. A transient process-identity failure must not prevent
            -- screen classification for that live target.
            if type(name) ~= "string" or name == "" then return nil, diagnostics end
            agent = name
            identity = identity or { job_id = nil, terminal_name = nil }
            identity.identity = identity.identity or { source = "registered", command = name }
            identity.probe_failed = true
            identity.diagnostics = diagnostics
        end

        local observation, screen_summary, status_cached = classify(bufnr, name, identity, true, options)
        local diagnostics = {}
        for _, message in ipairs(identity.diagnostics or {}) do diagnostics[#diagnostics + 1] = message end
        for _, message in ipairs(observation.diagnostics or {}) do diagnostics[#diagnostics + 1] = message end
        return {
            agent = agent,
            observation = vim.deepcopy(observation),
            identity = vim.deepcopy(identity.identity or {
                source = "unknown",
                command = name,
            }),
            screen = screen_summary,
            cache = { identity = identity_cached == true, status = status_cached },
            diagnostics = diagnostics,
        }
    end

    return {
        identify = process.identify,
        explain = explain,
        list = function(_, session_id, options)
            options = options or {}
            local result = {}
            for _, bufnr in ipairs(session_buffers(session_id)) do
                if valid_terminal(bufnr) then
                    local agent, identity = discover(bufnr, options.cache == true)
                    if agent then result[#result + 1] = row(bufnr, agent, identity, options) end
                else
                    identity_cache[bufnr] = nil
                    status_cache[bufnr] = nil
                    previous_observation[bufnr] = nil
                end
            end
            return result
        end,
        status = function(_, bufnr, name, options)
            if not valid_terminal(bufnr) then return nil end
            options = options or {}
            local _, identity = discover(bufnr, options.cache == true)
            local observation = classify(bufnr, name, identity, options.cache == true, options)
            return observation.state
        end,
    }
end

local default = M.new()
M.identify = default.identify
M.list = function(session_id, options) return default:list(session_id, options) end
M.status = function(bufnr, name, options) return default:status(bufnr, name, options) end
M.explain = function(bufnr, name, options) return default.explain(bufnr, name, options) end

return M
