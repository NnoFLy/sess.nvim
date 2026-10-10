local M = {}

local allowed_fields = {
    name = true,
    cwd = true,
    mark = true,
    pinned = true,
    last = true,
    current = true,
    active = true,
    agent = true,
    status = true,
    info = true,
}

local sort_modes = {
    default = true,
    recent = true,
    pinned = true,
    activity = true,
    name = true,
}

local function text(value)
    return value == nil and "" or tostring(value)
end

local function lower(value)
    return text(value):lower()
end

local function add(values, value)
    value = text(value)
    if value ~= "" then
        values[#values + 1] = value
    end
end

local function session_values(session, options)
    options = options or {}
    local metadata = session and session.metadata or {}
    local fields = {
        name = { text(metadata.name or session and session.name) },
        cwd = { text(metadata.cwd or session and session.path) },
        mark = {},
        pinned = {},
        last = {},
        current = {},
        active = {},
        agent = {},
        status = {},
        info = {},
    }

    add(fields.mark, options.mark)
    if metadata.pinned then
        add(fields.pinned, "pinned")
        add(fields.status, "pinned")
    end
    if options.previous then
        add(fields.last, "last")
        add(fields.status, "last")
    end
    if options.current then
        add(fields.current, "current")
        add(fields.status, "current")
    elseif options.active then
        add(fields.active, "active")
        add(fields.status, "active")
    else
        add(fields.status, "inactive")
    end

    local activity = options.current and 1 or 5
    for _, agent in ipairs(options.agents or {}) do
        add(fields.agent, agent.id)
        add(fields.agent, agent.name)
        add(fields.agent, agent.info)
        add(fields.status, agent.status or "unknown")
        add(fields.info, agent.info)
        if not options.current then
            local status = lower(agent.status)
            local rank = status == "working" and 2
                or status == "blocked" and 3
                or status == "idle" and 4
                or 5
            activity = math.min(activity, rank)
        end
    end

    local values = {}
    for field, entries in pairs(fields) do
        values[field] = table.concat(entries, " ")
    end
    values._activity = activity
    values._last_used_at = metadata.last_used_at or 0
    values._pinned = metadata.pinned == true
    values._id = session and session.id or ""
    return values
end

function M.allowed_fields()
    return vim.deepcopy(allowed_fields)
end

function M.validate(options)
    options = options or {}
    if options.fields ~= nil then
        if type(options.fields) ~= "table" then
            return false, "search.fields must be a list"
        end
        local seen = {}
        for index, field in ipairs(options.fields) do
            if type(field) ~= "string" or not allowed_fields[field] then
                return false, "search.fields[" .. index .. '] must be one of name, cwd, mark, pinned, last, current, active, agent, status, or info'
            end
            if seen[field] then
                return false, "search.fields must not contain duplicates"
            end
            seen[field] = true
        end
    end
    if options.filters ~= nil and type(options.filters) ~= "boolean" then
        return false, "search.filters must be a boolean"
    end
    if options.sort ~= nil and (type(options.sort) ~= "string" or not sort_modes[options.sort]) then
        return false, 'search.sort must be "default", "recent", "pinned", "activity", or "name"'
    end
    return true
end

function M.fields_for_session(session, options)
    return session_values(session, options)
end

function M.ordinal(fields)
    local order = {
        "name",
        "cwd",
        "mark",
        "pinned",
        "last",
        "current",
        "active",
        "agent",
        "status",
        "info",
    }
    local values = {}
    for _, field in ipairs(order) do
        values[#values + 1] = text(fields[field])
    end
    return table.concat(values, " ")
end

local function configured_fields(options)
    local fields = options and options.fields
    if type(fields) ~= "table" or #fields == 0 then
        return { "name", "cwd", "mark", "pinned", "last", "current", "active", "agent", "status", "info" }
    end
    return fields
end

function M.parse_filter(prompt, options)
    prompt = text(prompt)
    if not options or options.filters == false then
        return nil
    end

    if prompt:sub(1, 1) == "@" and #prompt > 1 and not prompt:find("%s") then
        return { field = "mark", query = prompt }
    end

    local field, query = prompt:match("^([%a_]+):(.*)$")
    local aliases = { path = "cwd", agent = "agent", status = "status" }
    if field and aliases[field] and query ~= "" then
        return { field = aliases[field], query = query }
    end
    -- Unknown, empty, or malformed filters are deliberately plain text. This
    -- keeps paths and shell-like names searchable without interpreting them.
    return nil
end

local function field_matches(fields, field, query)
    return lower(fields[field]):find(lower(query), 1, true) ~= nil
end

local function fuzzy_matches(value, query)
    value = lower(value)
    local start = 1
    for _, character in ipairs(vim.fn.split(query, "\\zs")) do
        local _, finish = value:find(character, start, true)
        if not finish then
            return false
        end
        start = finish + 1
    end
    return true
end

local function plain_matches(fields, query, options)
    query = lower(query)
    for _, field in ipairs(configured_fields(options)) do
        if field_matches(fields, field, query) or fuzzy_matches(fields[field], query) then
            return true
        end
    end
    return false
end

local function entry_fields(entry)
    return entry and entry.search_fields
        or entry and entry.value and entry.value.search_fields
        or {}
end

local function base_score(base, prompt, entry)
    if not base then
        return 1
    end
    local scorer = base.scoring_function or base.score
    if type(scorer) ~= "function" then
        return 1
    end

    -- Telescope calls scoring_function as (sorter, prompt, ordinal, entry).
    -- Keep the complete ordinal available to the configured sorter. Small
    -- custom sorters using (prompt, entry) are supported without invoking them
    -- twice, since scoring functions may have observable side effects.
    local ordinal = entry and entry.ordinal or ""
    local parameters = debug.getinfo(scorer, "u")
    local parameter_count = parameters and parameters.nparams or 0
    local ok, score
    if parameter_count >= 4 then
        ok, score = pcall(scorer, base, prompt, ordinal, entry)
    elseif parameter_count == 3 then
        ok, score = pcall(scorer, base, prompt, ordinal)
    else
        ok, score = pcall(scorer, prompt, entry)
    end
    if not ok or type(score) ~= "number" then
        return 1
    end
    return score
end

local function rank_bonus(fields, query)
    query = lower(query)
    local name = lower(fields.name)
    local mark = lower(fields.mark)
    if name == query then
        return 1000000
    elseif mark == query then
        return 900000
    elseif name:sub(1, #query) == query then
        return 100000
    elseif mark:sub(1, #query) == query then
        return 90000
    elseif lower(fields.cwd):find(query, 1, true) then
        return 1000
    end
    return 0
end

function M.new_sorter(base, options)
    options = options or {}
    local sorter = {}
    for key, value in pairs(base or {}) do
        sorter[key] = value
    end
    -- Telescope sorters expose lifecycle methods through their metatable.
    -- Copying fields alone leaves picker:find() unable to call _init/_destroy,
    -- which is especially visible when opening the active picker.
    local metatable = getmetatable(base)
    if metatable then
        setmetatable(sorter, metatable)
    end
    sorter._sess_search_sorter = true
    sorter.scoring_function = function(first, second, third, fourth)
        local prompt, entry
        if type(first) == "table" then
            -- Telescope's scoring_function receives the sorter as its first
            -- argument, followed by the prompt, ordinal, and entry.
            prompt, entry = second, fourth
        else
            -- Keep direct calls useful for integrations and unit tests.
            prompt, entry = first, second
        end
        local fields = entry_fields(entry)
        local filter = M.parse_filter(prompt, options)
        local query = filter and filter.query or prompt
        local plain_match = plain_matches(fields, query, options)
        if filter then
            if not allowed_fields[filter.field]
                or not field_matches(fields, filter.field, filter.query)
            then
                return -1
            end
        end

        local score_prompt = filter and filter.query or prompt
        if not filter and not plain_match then
            return -1
        end
        local score = base_score(base, score_prompt, entry)
        if score < 0 then
            return -1
        end
        return score + rank_bonus(fields, query)
    end
    return sorter
end

-- Active results are a tree: a session header and matching agent rows must
-- receive one score, otherwise Telescope's global sorter can split a group.
-- The row fields still perform filtering, while the group fields provide the
-- stable score used for every visible row in that group.
function M.new_active_sorter(base, options)
    local wrapped = base
    if not wrapped or not wrapped._sess_search_sorter then
        wrapped = M.new_sorter(base, options)
    end

    local sorter = {}
    for key, value in pairs(wrapped) do
        sorter[key] = value
    end
    local metatable = getmetatable(wrapped)
    if metatable then
        setmetatable(sorter, metatable)
    end

    local scoring = wrapped.scoring_function
    sorter._sess_search_sorter = true
    sorter._sess_active_sorter = true
    sorter.scoring_function = function(first, second, third, fourth)
        local has_sorter_argument = type(first) == "table"
        local entry = has_sorter_argument and fourth or second
        local group_fields = entry and entry.active_group_fields
        local group_ordinal = entry and entry.active_group_ordinal
        if not group_fields or not group_ordinal then
            return scoring(first, second, third, fourth)
        end

        local row_score = scoring(first, second, third, fourth)
        if row_score < 0 then
            return row_score
        end

        local group_entry = {
            ordinal = group_ordinal,
            search_fields = group_fields,
        }
        local group_score
        if has_sorter_argument then
            group_score = scoring(first, second, group_ordinal, group_entry)
        else
            group_score = scoring(first, group_entry)
        end
        return group_score >= 0 and group_score or row_score
    end
    return sorter
end

local function session_rank(session)
    local fields = session.search_fields or {}
    return fields._activity or 5
end

local function recent_value(session)
    local value = session.search_fields and session.search_fields._last_used_at
        or session.metadata and session.metadata.last_used_at
        or 0
    return tonumber(value) or 0
end

function M.sort_results(results, mode)
    mode = mode or "default"
    if mode == "default" then
        return results
    end
    local indexed = {}
    for index, result in ipairs(results or {}) do
        indexed[index] = { value = result, index = index }
    end
    table.sort(indexed, function(left, right)
        local a, b = left.value, right.value
        if mode == "name" then
            local an = lower(a.metadata and a.metadata.name or a.name)
            local bn = lower(b.metadata and b.metadata.name or b.name)
            if an ~= bn then
                return an < bn
            end
        elseif mode == "activity" then
            local ar = session_rank(a)
            local br = session_rank(b)
            if ar ~= br then
                return ar < br
            end
        elseif mode == "pinned" then
            local ap = a.metadata and a.metadata.pinned == true
            local bp = b.metadata and b.metadata.pinned == true
            if ap ~= bp then
                return ap
            end
        end
        if mode == "recent" or mode == "pinned" then
            local ar, br = recent_value(a), recent_value(b)
            if ar ~= br then
                return ar > br
            end
        end
        return left.index < right.index
    end)
    local sorted = {}
    for index, item in ipairs(indexed) do
        sorted[index] = item.value
    end
    return sorted
end

function M.sort_sessions(sessions, mode, options_for)
    local decorated = {}
    for index, session in ipairs(sessions or {}) do
        local value = vim.deepcopy(session)
        value.search_fields = session_values(session, options_for and options_for(session) or {})
        decorated[index] = value
    end
    local sorted = M.sort_results(decorated, mode)
    for _, session in ipairs(sorted) do
        session.search_fields = nil
    end
    return sorted
end

return M
