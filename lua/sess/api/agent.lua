local catalog = require("sess.session")
local detector = require("sess.agent.detect")
local editor = require("sess.editor")
local state = require("sess.state")
local scope = require("sess.lifecycle.operation_scope")

local M = {}
local allowed = { id = true, name = true, info = true, status = true, bufnr = true, winid = true }

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
    for _, agent in pairs(by_id) do
        -- Explicit integration status is authoritative. A registered agent
        -- without one gets the same screen-based fallback as auto-detected
        -- terminal agents.
        if not agent.status and agent.target and agent.target.bufnr then
            agent.status = detector.status(agent.target.bufnr, agent.name, probe_options)
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

    return vim.deepcopy(result), focused
end

-- Read the agent list and focused agent together. The active picker polls this
-- frequently, so resolving and discovering the same session twice is costly.
function M.snapshot(target)
    local item, err, _, diagnostics = resolve(target)
    if not item then
        return false, err, nil, nil, diagnostics
    end

    local result, focused = snapshot_for_id(item.id, false)
    return true, nil, result, focused, diagnostics
end

-- The active-session query already owns a validated runtime session record.
-- Avoid resolving that ID through the persistent catalog on every poll.
function M.snapshot_active(session_id)
    if type(session_id) ~= "string" or vim.trim(session_id) == "" then
        return false, "invalid active session id", nil, nil, {}
    end

    local result, focused = snapshot_for_id(session_id, true)
    return true, nil, result, focused, {}
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
    return true, nil, vim.deepcopy(all_agents(item.id)), diagnostics
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
