local catalog = require("sess.session")
local detector = require("sess.agent.detect")
local editor = require("sess.editor")
local state = require("sess.state")
local scope = require("sess.lifecycle.operation_scope")
local manifests = require("sess.agent.manifests")
local terminal_probe = require("sess.agent.terminal_probe")

local M = {}
local allowed = { id = true, name = true, info = true, status = true, bufnr = true, winid = true }
local terminal_liveness_cache = {}
local TERMINAL_LIVENESS_CACHE_TTL = 1000
local DEFAULT_REPORT_TTL = 30
local MAX_REPORT_TTL = 86400
local MAX_REPORT_SOURCE_LENGTH = 128
local MAX_REPORT_INFO_LENGTH = 240
local MAX_REPORT_SEQ = 9007199254740991
local MAX_REPORT_SOURCES = 32
local MAX_API_DIAGNOSTICS = 64
local report_statuses = { idle = true, working = true, blocked = true, done = true, unknown = true }

local function now_ms()
    local uv = vim.uv or vim.loop
    if uv and uv.hrtime then return uv.hrtime() / 1000000 end
    return os.clock() * 1000
end

local function resolve(target)
    if target == nil then
        target = state.get_current_session()
        if not target then
            return nil, "no current session", nil, {}
        end
    end

    local item, err, _, diagnostics = catalog.resolve(target)
    if not item then
        return nil, err, nil, diagnostics or {}
    end

    for _, active in ipairs(state.get_active_sessions()) do
        if active.id == item.id then
            return item, nil, nil, diagnostics or {}
        end
    end

    return nil, "session is not active: " .. item.id, nil, diagnostics or {}
end

local function string_field(value, name, required)
    if value == nil and not required then
        return true
    end
    if type(value) ~= "string" or vim.trim(value) == "" then
        return false, name .. " must be a non-empty string"
    end
    return true
end

local function valid_report_text(value, name, limit)
    if type(value) ~= "string" or value == "" or #value > limit then
        return false, name .. " must be bounded non-empty text"
    end
    return true
end

local function valid_report_seq(value)
    if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge
        or value < 0 or value % 1 ~= 0 or value > MAX_REPORT_SEQ
    then
        return false, "seq must be a non-negative integer within the supported range"
    end
    return true
end

local function utf8_width(byte)
    if byte and byte >= 194 and byte <= 223 then return 2 end
    if byte and byte >= 224 and byte <= 239 then return 3 end
    if byte and byte >= 240 and byte <= 244 then return 4 end
end

local function utf8_continuation(value, index)
    local byte = value:byte(index)
    if not byte or byte < 128 or byte > 191 then return false end
    local lead = index - 1
    while lead > 0 do
        local previous = value:byte(lead)
        if previous < 128 or previous > 191 then break end
        lead = lead - 1
    end
    local width = utf8_width(value:byte(lead))
    return width ~= nil and index - lead > 0 and index - lead < width
end

local function strip_report_controls(value)
    local result = {}
    for index = 1, #value do
        local byte = value:byte(index)
        local c1 = byte >= 128 and byte <= 159 and not utf8_continuation(value, index)
        if byte >= 32 and byte ~= 127 and not c1 then result[#result + 1] = string.char(byte) end
    end
    return table.concat(result)
end

local function truncate_text(value, limit)
    if #value <= limit then return value end
    local last = limit
    while last > 0 and value:byte(last) >= 128 and value:byte(last) <= 191 do last = last - 1 end
    local lead = last
    while lead > 1 and value:byte(lead - 1) >= 128 and value:byte(lead - 1) <= 191 do
        lead = lead - 1
    end
    local width = utf8_width(value:byte(lead))
    if width and last - lead + 1 < width then return value:sub(1, lead - 1) end
    return value:sub(1, last)
end

local function sanitize_report_text(value)
    if value == nil then return nil end
    value = value:gsub("\r", "")
    value = value:gsub("\27%][^\7]*\7", "")
    value = value:gsub("\27%][^\27]*\27\\", "")
    value = value:gsub("\27%[[0-?]*[ -/]*[@-~]", "")
    return truncate_text(strip_report_controls(value), MAX_REPORT_INFO_LENGTH)
end

local report_clock = now_ms

local function report_now()
    return report_clock()
end

-- A private clock seam keeps expiry tests deterministic without sleeping. It
-- is intentionally not part of the documented integration API.
function M._set_report_clock(clock)
    report_clock = type(clock) == "function" and clock or now_ms
end

local function append_diagnostic(result, value)
    if #result >= MAX_API_DIAGNOSTICS then
        result[MAX_API_DIAGNOSTICS] = "diagnostics truncated"
        return
    end
    local message = truncate_text(strip_report_controls(tostring(value or "unknown diagnostic")), MAX_REPORT_INFO_LENGTH)
    if message ~= "" then result[#result + 1] = message end
end

local valid_buffer_target
local terminal_buffer

local function target_incarnation(agent)
    local bufnr = agent and agent.target and agent.target.bufnr
    if not valid_buffer_target(bufnr) or not terminal_buffer(bufnr) then return nil end
    return terminal_probe.job_id(bufnr)
end

local function integration_details(session_id, agent_id, agent)
    local incarnation = target_incarnation(agent)
    state.prune_agent_reports(session_id, agent_id, incarnation)
    local reports = state.get_agent_reports(session_id, agent_id)
    local now = report_now()
    local selected
    local latest
    local latest_fresh = false
    local diagnostics = {}
    local sources = {}
    for source, report in pairs(reports) do
        if type(report) == "table" and type(report.accepted_at) == "number"
            and report.job_id == incarnation
        then
            sources[#sources + 1] = { source = source, report = report }
        elseif type(report) == "table" and report.job_id ~= incarnation then
            append_diagnostic(diagnostics, "integration report invalidated by target job replacement: " .. tostring(source))
        end
    end
    table.sort(sources, function(left, right)
        if left.report.accepted_at == right.report.accepted_at then
            return left.source < right.source
        end
        return left.report.accepted_at > right.report.accepted_at
    end)
    for _, entry in ipairs(sources) do
        local report = entry.report
        if not latest then latest = report end
        local source = entry.source
        if report.released then
            append_diagnostic(diagnostics, "integration source released: " .. source)
        elseif type(report.expires_at) == "number" and report.expires_at <= now then
            append_diagnostic(diagnostics, "integration report expired: " .. source)
        else
            if report == latest then latest_fresh = true end
            if report.status ~= "unknown" and not selected then selected = report end
        end
    end
    for _, rejection in ipairs(state.get_agent_report_rejections(session_id, agent_id)) do
        if type(rejection) == "table" and type(rejection.source) == "string" then
            append_diagnostic(
                diagnostics,
                "stale integration " .. (rejection.kind or "report") .. " rejected: " .. rejection.source
            )
        end
    end
    return selected and vim.deepcopy(selected) or nil, latest and vim.deepcopy(latest) or nil, diagnostics, latest_fresh
end

-- Keep the source table itself bounded even if a caller injects state through
-- a test double or an older runtime.
local function report_source_count(reports, incarnation)
    local count = 0
    for _, report in pairs(reports or {}) do
        if type(report) == "table" and report.job_id == incarnation then count = count + 1 end
    end
    return count
end

local function current_report(reports, source, incarnation)
    local report = reports and reports[source]
    if type(report) == "table" and report.job_id == incarnation then return report end
    return nil
end


local function valid_buffer(bufnr)
    if type(bufnr) ~= "number" or bufnr % 1 ~= 0 then
        return false, "bufnr must be an integer"
    end

    local ok, valid = pcall(vim.api.nvim_buf_is_valid, bufnr)
    if not ok or not valid then
        return false, "bufnr is not a valid buffer"
    end
    return true
end

local function valid_window(winid, bufnr)
    if winid == nil then
        return true
    end
    if type(winid) ~= "number" or winid % 1 ~= 0 then
        return false, "winid must be an integer"
    end

    local ok, valid = pcall(vim.api.nvim_win_is_valid, winid)
    if not ok or not valid then
        return false, "winid is not a valid window"
    end

    local got, value = pcall(vim.api.nvim_win_get_buf, winid)
    if not got or value ~= bufnr then
        return false, "winid does not contain bufnr"
    end
    return true
end

local function field_value(value)
    return value == vim.NIL and nil or value
end

local function validate(spec, partial, old)
    if type(spec) ~= "table" then
        return false, "agent spec must be a table"
    end

    for key in pairs(spec) do
        if not allowed[key] or (partial and key == "id") then
            return false, "unknown agent field: " .. key
        end
    end

    local previous = old or {}
    local previous_target = previous.target or {}
    local result = {
        id = field_value(spec.id) or previous.id,
        name = field_value(spec.name),
        info = field_value(spec.info),
        status = field_value(spec.status),
        target = {
            bufnr = field_value(spec.bufnr),
            winid = field_value(spec.winid),
        },
    }

    if partial then
        if spec.name == nil then result.name = previous.name end
        if spec.info == nil then result.info = previous.info end
        if spec.status == nil then result.status = previous.status end
        if spec.bufnr == nil then result.target.bufnr = previous_target.bufnr end
        if spec.winid == nil then result.target.winid = previous_target.winid end
    end

    local ok, err = string_field(result.id, "id", true)
    if not ok then return false, err end
    ok, err = string_field(result.name, "name", true)
    if not ok then return false, err end
    ok, err = string_field(result.info, "info", false)
    if not ok then return false, err end
    ok, err = string_field(result.status, "status", false)
    if not ok then return false, err end
    ok, err = valid_buffer(result.target.bufnr)
    if not ok then return false, err end
    ok, err = valid_window(result.target.winid, result.target.bufnr)
    if not ok then return false, err end

    return true, result
end

valid_buffer_target = function(bufnr)
    local ok, valid = pcall(vim.api.nvim_buf_is_valid, bufnr)
    return ok and valid
end

terminal_buffer = function(bufnr)
    if not valid_buffer_target(bufnr) then return false end
    local type_ok, buftype = pcall(function() return vim.bo[bufnr].buftype end)
    return type_ok and buftype == "terminal"
end

local function terminal_job_alive(bufnr, use_cache)
    local job_id = terminal_probe.job_id(bufnr)
    local now = now_ms()
    if use_cache then
        local cached = terminal_liveness_cache[bufnr]
        if cached
            and cached.job_id == job_id
            and now - cached.checked_at < TERMINAL_LIVENESS_CACHE_TTL
        then
            return cached.alive
        end
    else
        terminal_liveness_cache[bufnr] = nil
    end

    local ok, alive = pcall(terminal_probe.job_alive, bufnr)
    alive = ok and alive == true
    if use_cache then
        terminal_liveness_cache[bufnr] = { job_id = job_id, alive = alive, checked_at = now }
    end
    return alive
end

local function valid_terminal_target(bufnr, use_cache)
    return terminal_buffer(bufnr) and terminal_job_alive(bufnr, use_cache)
end

local function fallback_status(bufnr, name, probe_options)
    if type(detector.explain) == "function" then
        local ok, explanation, returned_diagnostics = pcall(detector.explain, bufnr, name, probe_options)
        if not ok then
            return "unknown", { "agent discovery probe failed: " .. tostring(explanation) }, true, nil
        end

        local diagnostics = {}
        local function append(values)
            if type(values) ~= "table" then return end
            for _, message in ipairs(values) do
                append_diagnostic(diagnostics, message)
                if #diagnostics >= MAX_API_DIAGNOSTICS then break end
            end
        end
        append(type(explanation) == "table" and explanation.diagnostics or nil)
        append(returned_diagnostics)

        local observation = type(explanation) == "table" and explanation.observation or nil
        if type(observation) == "table" and type(observation.state) == "string" then
            return observation.state, diagnostics, observation.probe_failed == true, observation
        end
        diagnostics[#diagnostics + 1] = "agent discovery returned no status"
        return "unknown", diagnostics, true, nil
    end

    -- Keep compatibility with older detector implementations that only expose
    -- the string status API. Current discovery always takes the structured path.
    local ok, status = pcall(detector.status, bufnr, name, probe_options)
    if ok and type(status) == "string" then return status, {}, false, nil end
    return "unknown", { "agent status probe unavailable" }, true, nil
end

local function all_agents(session_id, use_cache)
    local by_id = state.get_agents(session_id)
    local registered_agents = {}
    local by_buffer = {}
    for id, agent in pairs(by_id) do
        registered_agents[id] = agent
        if agent.target and agent.target.bufnr then
            by_buffer[agent.target.bufnr] = true
        end
    end

    local probe_options = {
        cache = use_cache == true,
        -- Active snapshots already validate terminal liveness above and use
        -- the API's short liveness cache. Avoid probing each terminal twice.
        target_validated = use_cache == true,
    }
    local discovery_diagnostic
    local discovered_ok, discovered_agents = pcall(detector.list, session_id, probe_options)
    if not discovered_ok then
        discovery_diagnostic = "agent discovery failed: " .. tostring(discovered_agents)
        discovered_agents = {}
    elseif type(discovered_agents) ~= "table" then
        discovery_diagnostic = "agent discovery returned malformed agents"
        discovered_agents = {}
    end
    for _, agent in ipairs(discovered_agents) do
        if type(agent) == "table" and agent.id and agent.target and agent.target.bufnr
            and not by_id[agent.id] and not by_buffer[agent.target.bufnr]
        then
            by_id[agent.id] = agent
            by_buffer[agent.target.bufnr] = true
        end
    end

    local result = {}
    for _, stored_agent in pairs(by_id) do
        local agent = vim.deepcopy(stored_agent)
        local bufnr = agent.target and agent.target.bufnr
        local target_valid = bufnr and valid_buffer_target(bufnr)
        local terminal_target = target_valid and terminal_buffer(bufnr)
        local target_unavailable = not target_valid
        local registered_agent = registered_agents[agent.id]
        local manual_status = registered_agent and registered_agent.status or nil
        local has_reports = next(state.get_agent_reports(session_id, agent.id)) ~= nil
        -- Synchronous list/explain calls force a liveness probe. Active picker
        -- snapshots may use the short cache only for plain screen discovery;
        -- explicit/manual or sequenced authorities are checked immediately.
        local liveness_cache = use_cache == true and not manual_status and not has_reports
        local terminal_alive = terminal_target and terminal_job_alive(bufnr, liveness_cache)
        local terminal_job_unavailable = terminal_target and not terminal_alive
        local selected_report, _, integration_diagnostics = integration_details(session_id, agent.id, agent)
        local diagnostics = vim.deepcopy(integration_diagnostics)
        if discovery_diagnostic then append_diagnostic(diagnostics, discovery_diagnostic) end
        probe_options.integration = nil
        if selected_report then
            agent.status = selected_report.status
            agent.info = selected_report.info
            probe_options.integration = selected_report
        end

        if target_unavailable or terminal_job_unavailable then
            -- A registered status cannot remain authoritative after its target
            -- disappears or its terminal job exits. Keep the record for explicit
            -- cleanup, but expose a safe unknown result instead of old state.
            agent.status = "unknown"
            agent.source = "unknown"
            agent.authority = "none"
            local message = "registered agent target is unavailable; integration status is stale"
            if terminal_job_unavailable then
                message = "registered agent terminal job is no longer running; integration status is stale"
            end
            diagnostics[#diagnostics + 1] = message
        elseif selected_report and not terminal_target then
            -- Runtime reports are useful for explicitly registered non-terminal
            -- targets too; there is no screen probe to arbitrate in that case.
            agent.source = "integration"
            agent.authority = "lifecycle"
        elseif selected_report or not manual_status then
            -- Screen probing is terminal-only. New reports are passed to the
            -- detector so a high-confidence current blocker can override a
            -- non-blocking lifecycle state.
            if terminal_target and terminal_alive then
                local status, probe_messages, probe_failed, observation = fallback_status(
                    agent.target.bufnr,
                    agent.name,
                    probe_options
                )
                agent.status = status
                agent.source = observation and observation.source or (selected_report and "integration" or "unknown")
                agent.authority = observation and observation.authority
                    or (selected_report and "lifecycle" or "none")
                agent.stale = observation and observation.stale == true or false
                if observation and observation.evidence then agent.evidence = vim.deepcopy(observation.evidence) end
                if probe_failed then agent.probe_failed = true end
                for _, message in ipairs(probe_messages or {}) do append_diagnostic(diagnostics, message) end
            else
                agent.status = "unknown"
                agent.source = "unknown"
                agent.authority = "none"
                diagnostics[#diagnostics + 1] = "screen status probe requires a terminal target"
            end
        elseif manual_status then
            agent.source = "integration"
            agent.authority = "manual"
        end
        if #diagnostics > 0 then agent.diagnostics = vim.deepcopy(diagnostics) end
        result[#result + 1] = agent
    end
    table.sort(result, function(a, b)
        return a.id < b.id
    end)
    return result
end

local function snapshot_for_id(session_id, use_cache)
    local result = all_agents(session_id, use_cache)
    local focused_id = state.get_focused_agent_id(session_id)
    local focused
    if focused_id then
        for _, agent in ipairs(result) do
            if agent.id == focused_id then
                focused = agent.id
                break
            end
        end
    end

    local diagnostics = {}
    for _, agent in ipairs(result) do
        for _, message in ipairs(agent.diagnostics or {}) do
            append_diagnostic(diagnostics, message)
        end
    end
    return vim.deepcopy(result), focused, diagnostics
end

-- Read the agent list and focused agent together. The active picker polls this
-- frequently, so resolving and discovering the same session twice is costly.
function M.snapshot(target)
    local item, err, _, diagnostics = resolve(target)
    if not item then
        return false, err, nil, nil, diagnostics
    end

    local result, focused, agent_diagnostics = snapshot_for_id(item.id, false)
    diagnostics = vim.list_extend(diagnostics or {}, agent_diagnostics)
    return true, nil, result, focused, diagnostics
end

-- The active-session query already owns a validated runtime session record.
-- Avoid resolving that ID through the persistent catalog on every poll.
function M.snapshot_active(session_id)
    if type(session_id) ~= "string" or vim.trim(session_id) == "" then
        return false, "invalid active session id", nil, nil, {}
    end

    local result, focused, diagnostics = snapshot_for_id(session_id, true)
    return true, nil, result, focused, diagnostics
end

function M.register(target, spec)
    if scope.is_busy() then return false, "session transition already in progress" end
    local item, err, _, diagnostics = resolve(target)
    if not item then return false, err, nil, diagnostics end

    local ok, result = validate(spec, false)
    if not ok then return false, result, nil, diagnostics end
    if state.get_agents(item.id)[result.id] then
        return false, "agent already registered: " .. result.id, nil, diagnostics
    end

    state.set_agent(item.id, result)
    return true, nil, vim.deepcopy(result), diagnostics
end

function M.update(target, agent_id, patch)
    if scope.is_busy() then return false, "session transition already in progress" end
    local item, err, _, diagnostics = resolve(target)
    if not item then return false, err, nil, diagnostics end

    local old = state.get_agents(item.id)[agent_id]
    if not old then return false, "agent not found: " .. tostring(agent_id), nil, diagnostics end

    local ok, result = validate(patch, true, old)
    if not ok then return false, result, nil, diagnostics end
    result.id = old.id
    state.set_agent(item.id, result)
    return true, nil, vim.deepcopy(result), diagnostics
end

local function validate_report(report, release)
    if type(report) ~= "table" then return false, "agent report must be a table" end
    local allowed = release and { source = true, seq = true }
        or { source = true, seq = true, status = true, info = true, ttl = true }
    for key in pairs(report) do
        if not allowed[key] then return false, "unknown agent report field: " .. tostring(key) end
    end
    local ok, err = valid_report_text(report.source, "source", MAX_REPORT_SOURCE_LENGTH)
    if not ok then return false, err end
    if #vim.trim(report.source) ~= #report.source then return false, "source must not have surrounding whitespace" end
    if strip_report_controls(report.source) ~= report.source then
        return false, "source contains control characters"
    end
    ok, err = valid_report_seq(report.seq)
    if not ok then return false, err end
    if not release then
        if not report_statuses[report.status] then
            return false, "status must be idle, working, blocked, done, or unknown"
        end
        if report.info ~= nil then
            ok, err = valid_report_text(report.info, "info", MAX_REPORT_INFO_LENGTH)
            if not ok then return false, err end
        end
        if report.ttl ~= nil then
            if type(report.ttl) ~= "number" or report.ttl ~= report.ttl
                or report.ttl == math.huge or report.ttl == -math.huge
                or report.ttl <= 0 or report.ttl >= MAX_REPORT_TTL
            then
                return false, "ttl must be a finite positive number below the maximum"
            end
        end
    end
    return true
end

local function target_available(agent)
    local bufnr = agent and agent.target and agent.target.bufnr
    if not valid_buffer_target(bufnr) then return false end
    return not terminal_buffer(bufnr) or terminal_job_alive(bufnr, false)
end

function M.report(target, agent_id, report)
    if scope.is_busy() then return false, "session transition already in progress" end
    local item, err, _, diagnostics = resolve(target)
    if not item then return false, err, nil, diagnostics end
    local agent = state.get_agents(item.id)[agent_id]
    if not agent then return false, "agent not found: " .. tostring(agent_id), nil, diagnostics end
    if not target_available(agent) then
        return false, "agent target is unavailable", nil, vim.list_extend(diagnostics or {}, {
            "integration report rejected because its target is unavailable",
        })
    end
    local valid, validation_error = validate_report(report, false)
    if not valid then return false, validation_error, nil, diagnostics end
    local reports = state.get_agent_reports(item.id, agent_id)
    local incarnation = target_incarnation(agent)
    local previous = current_report(reports, report.source, incarnation)
    if previous and report.seq <= previous.seq then
        state.record_agent_report_rejection(item.id, agent_id, {
            source = report.source,
            seq = report.seq,
            accepted_seq = previous.seq,
            kind = "report",
        })
        return false,
            "stale integration report sequence for source " .. report.source,
            nil,
            vim.list_extend(diagnostics or {}, { "integration report rejected as stale" })
    end
    if not previous and report_source_count(reports, incarnation) >= MAX_REPORT_SOURCES
        and reports[report.source] == nil
    then
        return false, "integration report source limit exceeded", nil, diagnostics
    end
    local accepted_at = report_now()
    local accepted = {
        source = report.source,
        seq = report.seq,
        status = report.status,
        info = sanitize_report_text(report.info),
        accepted_at = accepted_at,
        expires_at = accepted_at + (report.ttl or DEFAULT_REPORT_TTL) * 1000,
        job_id = incarnation,
        released = false,
    }
    state.set_agent_report(item.id, agent_id, report.source, accepted)
    local returned = vim.deepcopy(agent)
    returned.status = accepted.status
    returned.info = accepted.info
    returned.source = "integration"
    returned.authority = "lifecycle"
    returned.integration = vim.deepcopy(accepted)
    return true, nil, returned, diagnostics
end

function M.release(target, agent_id, release)
    if scope.is_busy() then return false, "session transition already in progress" end
    local item, err, _, diagnostics = resolve(target)
    if not item then return false, err, nil, diagnostics end
    local agent = state.get_agents(item.id)[agent_id]
    if not agent then return false, "agent not found: " .. tostring(agent_id), nil, diagnostics end
    if not target_available(agent) then
        return false, "agent target is unavailable", nil, vim.list_extend(diagnostics or {}, {
            "integration release target is unavailable",
        })
    end
    local valid, validation_error = validate_report(release, true)
    if not valid then return false, validation_error, nil, diagnostics end
    local reports = state.get_agent_reports(item.id, agent_id)
    local incarnation = target_incarnation(agent)
    local previous = current_report(reports, release.source, incarnation)
    if previous and release.seq <= previous.seq then
        state.record_agent_report_rejection(item.id, agent_id, {
            source = release.source,
            seq = release.seq,
            accepted_seq = previous.seq,
            kind = "release",
        })
        return false,
            "stale integration release sequence for source " .. release.source,
            nil,
            vim.list_extend(diagnostics or {}, { "integration release rejected as stale" })
    end
    if not previous and report_source_count(reports, incarnation) >= MAX_REPORT_SOURCES
        and reports[release.source] == nil
    then
        return false, "integration report source limit exceeded", nil, diagnostics
    end
    local accepted_at = report_now()
    state.set_agent_report(item.id, agent_id, release.source, {
        source = release.source,
        seq = release.seq,
        status = "unknown",
        accepted_at = accepted_at,
        expires_at = accepted_at,
        job_id = incarnation,
        released = true,
    })
    local released = state.get_agent_reports(item.id, agent_id)[release.source]
    local current = all_agents(item.id, false)
    for _, candidate in ipairs(current) do
        if candidate.id == agent_id then
            candidate.integration = vim.deepcopy(released)
            return true, nil, vim.deepcopy(candidate), diagnostics
        end
    end
    local returned = vim.deepcopy(agent)
    returned.integration = vim.deepcopy(released)
    return true, nil, returned, diagnostics
end

function M.unregister(target, agent_id)
    if scope.is_busy() then return false, "session transition already in progress" end
    local item, err, _, diagnostics = resolve(target)
    if not item then return false, err, nil, diagnostics end

    local removed = state.remove_agent(item.id, agent_id)
    if not removed then return false, "agent not found: " .. tostring(agent_id), nil, diagnostics end
    return true, nil, removed, diagnostics
end

function M.list(target)
    local item, err, _, diagnostics = resolve(target)
    if not item then return false, err, nil, diagnostics end
    local result = all_agents(item.id)
    diagnostics = vim.deepcopy(diagnostics or {})
    for _, agent in ipairs(result) do
        if type(agent.diagnostics) == "table" then
            for _, message in ipairs(agent.diagnostics) do
                append_diagnostic(diagnostics, message)
            end
        end
    end
    return true, nil, vim.deepcopy(result), diagnostics
end

function M.focus(target, agent_id)
    if scope.is_busy() then return false, "session transition already in progress" end
    local item, err, _, diagnostics = resolve(target)
    if not item then return false, err, nil, diagnostics end

    local current = state.get_current_session()
    if not current or current.id ~= item.id then
        return false, "agent session is not current", nil, diagnostics
    end

    local agent
    for _, candidate in ipairs(all_agents(item.id)) do
        if candidate.id == agent_id then
            agent = candidate
            break
        end
    end
    if not agent then
        return false, "agent not found: " .. tostring(agent_id), nil, diagnostics
    end

    local focused, win_or_err = editor.focus_buffer(agent.target.bufnr, agent.target.winid)
    if not focused then
        return true, nil, agent, vim.list_extend(diagnostics or {}, { win_or_err or "agent target is unavailable" })
    end

    agent.target.winid = win_or_err
    -- Focusing must not register derived status as an explicit override.
    local registered = state.get_agents(item.id)[agent.id]
    if registered then
        registered.target.winid = win_or_err
        state.set_agent(item.id, registered)
    end
    state.set_focused_agent(item.id, agent.id)
    return true, nil, vim.deepcopy(agent), diagnostics
end

local function bounded_text(value, limit)
    if value == nil then return nil end
    value = tostring(value):gsub("\r", "")
    value = value:gsub("\27%][^\7]*\7", "")
    value = value:gsub("\27%][^\27]*\27\\", "")
    value = value:gsub("\27%[[0-?]*[ -/]*[@-~]", "")
    return truncate_text(strip_report_controls(value), limit)
end

local function bounded_list(values, limit, max_items)
    local result = {}
    if type(values) ~= "table" then return result end
    for index, value in ipairs(values) do
        if index > max_items then break end
        local item = bounded_text(value, limit)
        if item and item ~= "" then result[#result + 1] = item end
    end
    return result
end

local function identity_details(value, fallback_name)
    value = type(value) == "table" and value or {}
    return {
        source = bounded_text(value.source or "unknown", 80),
        command = bounded_text(value.command or fallback_name, 240),
        pid = type(value.pid) == "number" and value.pid or nil,
    }
end

local function screen_details(value)
    if type(value) ~= "table" then
        return { changedtick = nil, line_count = 0, complete = false }
    end
    return {
        changedtick = type(value.changedtick) == "number" and value.changedtick or nil,
        line_count = type(value.line_count) == "number" and math.max(0, math.min(value.line_count, 200)) or 0,
        complete = value.complete == true,
        error = bounded_text(value.error, 240),
    }
end

local function cache_details(value)
    value = type(value) == "table" and value or {}
    return { identity = value.identity == true, status = value.status == true }
end

local function rule_details(observation)
    if type(observation) ~= "table" or type(observation.rule_id) ~= "string" then return nil end
    local manifest = manifests[observation.manifest_id]
    if type(manifest) ~= "table" then return { id = observation.rule_id } end
    for _, rule in ipairs(manifest.rules or {}) do
        if rule.id == observation.rule_id then
            return { id = rule.id, priority = rule.priority }
        end
    end
    return { id = observation.rule_id }
end

-- Explain is deliberately separate from list rows: screen evidence and probe
-- metadata are bounded diagnostics, not part of the compact public record.
function M.explain(target, agent_id)
    local item, err, _, resolution_diagnostics = resolve(target)
    if not item then return false, err, nil, resolution_diagnostics end
    if type(agent_id) ~= "string" or vim.trim(agent_id) == "" then
        return false, "agent id must be a non-empty string", nil, resolution_diagnostics
    end

    local agent
    for _, candidate in ipairs(all_agents(item.id, true)) do
        if candidate.id == agent_id then
            agent = candidate
            break
        end
    end
    if not agent then
        return false, "agent not found: " .. agent_id, nil, resolution_diagnostics
    end

    local registered = state.get_agents(item.id)[agent.id]
    local observed_target = registered or agent
    local registered_target_available = target_available(observed_target)
    local selected_report, latest_report, integration_diagnostics, latest_report_fresh = integration_details(
        item.id,
        agent.id,
        observed_target
    )
    -- A deleted buffer or exited job is an unavailable target, regardless of
    -- what a runtime report said before that transition.
    local target_unavailable = not registered_target_available
    if target_unavailable then selected_report = nil end
    local explicit_status = registered_target_available and registered and registered.status or nil
    local integration_status = selected_report or explicit_status
    local integration_option = selected_report or (explicit_status and {
        state = explicit_status,
        status = explicit_status,
        manual = true,
    } or nil)
    local probe_result, probe_diagnostics
    if not target_unavailable
        and valid_terminal_target(agent.target and agent.target.bufnr, false)
        and type(detector.explain) == "function"
    then
        local probe_ok, result, diagnostics = pcall(detector.explain, agent.target.bufnr, agent.name, integration_option and {
            integration = integration_option,
        } or {})
        if probe_ok then
            probe_result, probe_diagnostics = result, diagnostics
        else
            probe_diagnostics = { "agent explanation probe failed: " .. tostring(result) }
        end
    end
    if type(probe_diagnostics) ~= "table" then probe_diagnostics = {} end
    if type(probe_result) ~= "table" and #probe_diagnostics == 0 and not integration_status then
        probe_diagnostics[1] = "agent observation unavailable"
    end

    local probe = type(probe_result) == "table" and probe_result or {}
    local observation = type(probe.observation) == "table" and probe.observation or {
        state = (not target_unavailable and selected_report and selected_report.status) or explicit_status or "unknown",
        source = (not target_unavailable and integration_status) and "integration" or "unknown",
        authority = (not target_unavailable and integration_status) and "lifecycle" or "none",
        manifest_id = agent.name,
        manifest_version = manifests[agent.name] and manifests[agent.name].version or nil,
        evidence = {},
        diagnostics = {},
    }
    local diagnostics = {}
    for _, message in ipairs(resolution_diagnostics or {}) do diagnostics[#diagnostics + 1] = bounded_text(message, 240) end
    for _, message in ipairs(probe_diagnostics or {}) do diagnostics[#diagnostics + 1] = bounded_text(message, 240) end
    for _, message in ipairs(integration_diagnostics or {}) do diagnostics[#diagnostics + 1] = bounded_text(message, 240) end
    if type(observation.diagnostics) == "table" then
        for _, message in ipairs(observation.diagnostics) do
            local bounded = bounded_text(message, 240)
            if bounded then diagnostics[#diagnostics + 1] = bounded end
        end
    end

    local manifest_id = observation.manifest_id or agent.name
    local manifest_version = observation.manifest_version
    local manifest = manifests[manifest_id]
    if manifest_version == nil and manifest then manifest_version = manifest.version end
    local latest_integration = selected_report or latest_report
    local explanation = {
        id = agent.id,
        name = agent.name,
        status = target_unavailable and "unknown" or (observation.state or explicit_status or "unknown"),
        source = target_unavailable and "unknown" or (observation.source or (integration_status and "integration" or "unknown")),
        authority = target_unavailable and "none" or (observation.authority or (integration_status and "lifecycle" or "none")),
        target = vim.deepcopy(agent.target),
        identity = identity_details(
            probe.identity or {
                source = explicit_status and "registered" or "unknown",
                command = agent.name,
            },
            agent.name
        ),
        manifest = { id = manifest_id, version = manifest_version },
        matched_rule = rule_details(observation),
        evidence = bounded_list(observation.evidence, 240, 3),
        screen = screen_details(probe.screen),
        cache = cache_details(probe.cache),
        integration = latest_integration and {
            source = bounded_text(latest_integration.source, MAX_REPORT_SOURCE_LENGTH),
            seq = latest_integration.seq,
            accepted_at = latest_integration.accepted_at,
            expires_at = latest_integration.expires_at,
            fresh = not target_unavailable and (selected_report ~= nil or latest_report_fresh == true),
            released = latest_integration.released == true,
            info = bounded_text(latest_integration.info, MAX_REPORT_INFO_LENGTH),
        } or nil,
        diagnostics = diagnostics,
    }
    return true, nil, vim.deepcopy(explanation), diagnostics
end

function M.focused(target)
    local item, err, _, diagnostics = resolve(target)
    if not item then return false, err, nil, diagnostics end

    local id = state.get_focused_agent_id(item.id)
    if not id then
        return true, nil, nil, diagnostics
    end

    for _, agent in ipairs(all_agents(item.id)) do
        if agent.id == id then
            return true, nil, agent, diagnostics
        end
    end

    return true, nil, nil, diagnostics
end

return M
