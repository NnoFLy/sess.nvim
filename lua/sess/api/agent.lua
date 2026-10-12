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
local TERMINAL_LIVENESS_CACHE_TTL = 500

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

local function valid_buffer_target(bufnr)
    local ok, valid = pcall(vim.api.nvim_buf_is_valid, bufnr)
    return ok and valid
end

local function terminal_buffer(bufnr)
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
            return "unknown", { "agent discovery probe failed: " .. tostring(explanation) }, true
        end

        local diagnostics = {}
        local function append(values)
            if type(values) ~= "table" then return end
            for _, message in ipairs(values) do
                diagnostics[#diagnostics + 1] = tostring(message)
            end
        end
        append(type(explanation) == "table" and explanation.diagnostics or nil)
        append(returned_diagnostics)

        local observation = type(explanation) == "table" and explanation.observation or nil
        if type(observation) == "table" and type(observation.state) == "string" then
            return observation.state, diagnostics, observation.probe_failed == true
        end
        diagnostics[#diagnostics + 1] = "agent discovery returned no status"
        return "unknown", diagnostics, true
    end

    -- Keep compatibility with older detector implementations that only expose
    -- the string status API. Current discovery always takes the structured path.
    local ok, status = pcall(detector.status, bufnr, name, probe_options)
    if ok and type(status) == "string" then return status, {}, false end
    return "unknown", { "agent status probe unavailable" }, true
end

local function all_agents(session_id, use_cache)
    local by_id = state.get_agents(session_id)
    local by_buffer = {}
    for _, agent in pairs(by_id) do
        if agent.target and agent.target.bufnr then
            by_buffer[agent.target.bufnr] = true
        end
    end

    local probe_options = { cache = use_cache == true }
    for _, agent in ipairs(detector.list(session_id, probe_options)) do
        if not by_id[agent.id] and not by_buffer[agent.target.bufnr] then
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
        local terminal_job_unavailable = terminal_target and not terminal_job_alive(bufnr, use_cache)
        if target_unavailable or terminal_job_unavailable then
            -- A registered status cannot remain authoritative after its target
            -- disappears or its terminal job exits. Keep the record for explicit
            -- cleanup, but expose a safe unknown result instead of old state.
            agent.status = "unknown"
            local message = "registered agent target is unavailable; integration status is stale"
            if terminal_job_unavailable then
                message = "registered agent terminal job is no longer running; integration status is stale"
            end
            agent.diagnostics = { message }
        elseif not agent.status and agent.target and agent.target.bufnr then
            -- Screen probing is terminal-only. Non-terminal registered targets
            -- without an explicit status remain safely unknown.
            if valid_terminal_target(agent.target.bufnr, use_cache) then
                local status, diagnostics, probe_failed = fallback_status(
                    agent.target.bufnr,
                    agent.name,
                    probe_options
                )
                agent.status = status
                if probe_failed then agent.probe_failed = true end
                if #diagnostics > 0 then agent.diagnostics = diagnostics end
            else
                agent.status = "unknown"
                agent.diagnostics = { "screen status probe requires a terminal target" }
            end
        end
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
            diagnostics[#diagnostics + 1] = message
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
                diagnostics[#diagnostics + 1] = message
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
    if #value > limit then value = value:sub(1, limit) end
    return value
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
    local registered_bufnr = registered and registered.target and registered.target.bufnr
    local registered_target_available = registered
        and registered.target
        and valid_buffer_target(registered_bufnr)
        and (not terminal_buffer(registered_bufnr) or terminal_job_alive(registered_bufnr, true))
    local explicit_status = registered_target_available and registered.status or nil
    local probe_result, probe_diagnostics
    if valid_terminal_target(agent.target and agent.target.bufnr, true)
        and type(detector.explain) == "function"
    then
        local probe_ok, result, diagnostics = pcall(detector.explain, agent.target.bufnr, agent.name, explicit_status and {
            integration = { state = explicit_status },
        } or {})
        if probe_ok then
            probe_result, probe_diagnostics = result, diagnostics
        else
            probe_diagnostics = { "agent explanation probe failed: " .. tostring(result) }
        end
    end
    if type(probe_diagnostics) ~= "table" then probe_diagnostics = {} end
    if type(probe_result) ~= "table" and #probe_diagnostics == 0 and not explicit_status then
        probe_diagnostics[1] = "agent observation unavailable"
    end

    local observation = type(probe_result) == "table" and type(probe_result.observation) == "table" and probe_result.observation or {
        state = explicit_status or "unknown",
        source = explicit_status and "integration" or "unknown",
        manifest_id = agent.name,
        manifest_version = manifests[agent.name] and manifests[agent.name].version or nil,
        evidence = {},
        diagnostics = {},
    }
    local diagnostics = {}
    for _, message in ipairs(resolution_diagnostics or {}) do diagnostics[#diagnostics + 1] = bounded_text(message, 240) end
    for _, message in ipairs(probe_diagnostics or {}) do diagnostics[#diagnostics + 1] = bounded_text(message, 240) end
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
    local explanation = {
        id = agent.id,
        name = agent.name,
        status = observation.state or explicit_status or "unknown",
        source = observation.source or (explicit_status and "integration" or "unknown"),
        target = vim.deepcopy(agent.target),
        identity = identity_details(
            type(probe_result) == "table" and probe_result.identity or {
                source = explicit_status and "registered" or "unknown",
                command = agent.name,
            },
            agent.name
        ),
        manifest = { id = manifest_id, version = manifest_version },
        matched_rule = rule_details(observation),
        evidence = bounded_list(observation.evidence, 240, 3),
        screen = screen_details(type(probe_result) == "table" and probe_result.screen or nil),
        cache = cache_details(type(probe_result) == "table" and probe_result.cache or nil),
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
