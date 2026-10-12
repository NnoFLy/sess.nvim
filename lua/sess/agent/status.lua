local manifests = require("sess.agent.manifests")

local M = {}

local MAX_LINES = 200
local MAX_LINE_LENGTH = 1000
local MAX_TOTAL_LINE_BYTES = 65536
local MAX_EVIDENCE_LINES = 3
local MAX_EVIDENCE_LENGTH = 240
local MAX_MATCHER_DEPTH = 16
local MAX_PATTERN_LENGTH = 256
local MAX_MATCHER_ITEMS = 64
local MAX_RULES = 128
local MAX_STATUS_LENGTH = 240

local regions = {
    current_prompt = true,
    before_current_prompt = true,
    bottom_non_empty = true,
    recent = true,
    top_non_empty = true,
    osc_title = true,
}

local function truncate(value, limit)
    if #value <= limit then return value end
    local result = value:sub(1, limit)
    while #result > 0 and result:byte(-1) >= 128 and result:byte(-1) <= 191 do
        result = result:sub(1, -2)
    end
    return result
end

local function clean(value)
    value = tostring(value):gsub("\r", "")
    value = value:gsub("\27%][^\7]*\7", "")
    value = value:gsub("\27%][^\27]*\27\\", "")
    value = value:gsub("\27%[[0-?]*[ -/]*[@-~]", "")
    local result = {}
    for index = 1, #value do
        local byte = value:byte(index)
        local continuation = false
        if byte >= 128 and byte <= 191 and index > 1 then
            local lead = value:byte(index - 1)
            continuation = lead >= 194 and lead <= 244
        end
        if byte >= 32 and not (byte >= 127 and byte <= 159) or byte >= 160 or continuation then
            result[#result + 1] = string.char(byte)
        elseif byte == 9 then
            result[#result + 1] = "\t"
        end
    end
    return truncate(table.concat(result), MAX_LINE_LENGTH)
end

local function diagnostic(diagnostics, message)
    diagnostics[#diagnostics + 1] = truncate(message, MAX_EVIDENCE_LENGTH)
end

local function is_array(value)
    if type(value) ~= "table" or #value == 0 or #value > MAX_MATCHER_ITEMS then return false end
    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > #value then
            return false
        end
        count = count + 1
    end
    return count == #value
end

local function validate_matcher(matcher, path, depth)
    if type(matcher) ~= "table" then return false, path .. " must be a matcher table" end
    if depth > MAX_MATCHER_DEPTH then return false, path .. " is too deeply nested" end

    local key_count = 0
    for _ in pairs(matcher) do
        key_count = key_count + 1
        if key_count > MAX_MATCHER_ITEMS then return false, path .. " has too many fields" end
    end
    local operator
    for _, key in ipairs({ "contains", "contains_any", "regex", "any", "all", "not" }) do
        if matcher[key] ~= nil then
            if operator then return false, path .. " has multiple matcher operators" end
            operator = key
        end
    end
    if not operator or key_count ~= 1 then return false, path .. " has an invalid matcher" end

    if operator == "contains" or operator == "regex" then
        if type(matcher[operator]) ~= "string" or matcher[operator] == "" then
            return false, path .. "." .. operator .. " must be a non-empty string"
        end
        if #matcher[operator] > MAX_PATTERN_LENGTH then
            return false, path .. "." .. operator .. " is too long"
        end
        if operator == "regex" then
            local ok, err = pcall(string.find, "", matcher.regex)
            if not ok then return false, path .. ".regex is invalid: " .. tostring(err) end
        end
    elseif operator == "contains_any" then
        if not is_array(matcher.contains_any) then
            return false, path .. ".contains_any must be a non-empty list"
        end
        for index, value in ipairs(matcher.contains_any) do
            if type(value) ~= "string" or value == "" or #value > MAX_PATTERN_LENGTH then
                return false, path .. ".contains_any[" .. index .. "] must be a bounded string"
            end
        end
    elseif operator == "any" or operator == "all" then
        if not is_array(matcher[operator]) then return false, path .. "." .. operator .. " must be a non-empty list" end
        for index, child in ipairs(matcher[operator]) do
            local valid, err = validate_matcher(child, path .. "." .. operator .. "[" .. index .. "]", depth + 1)
            if not valid then return false, err end
        end
    elseif operator == "not" then
        if is_array(matcher["not"]) then
            for index, child in ipairs(matcher["not"]) do
                local valid, err = validate_matcher(child, path .. ".not[" .. index .. "]", depth + 1)
                if not valid then return false, err end
            end
        else
            local valid, err = validate_matcher(matcher["not"], path .. ".not", depth + 1)
            if not valid then return false, err end
        end
    end
    return true
end

local function validate_line_list(value, field, diagnostics)
    if value == nil then return true end
    if type(value) ~= "table" then
        diagnostic(diagnostics, "screen snapshot " .. field .. " must be a table")
        return false
    end

    local valid, count, bytes = true, 0, 0
    for index, line in pairs(value) do
        count = count + 1
        if count > MAX_LINES then
            diagnostic(diagnostics, "screen snapshot " .. field .. " has too many lines")
            return false
        end
        if type(index) ~= "number" or index % 1 ~= 0 or index < 1 or index > MAX_LINES then
            diagnostic(diagnostics, "screen snapshot " .. field .. " has an invalid line index")
            valid = false
        elseif type(line) ~= "string" then
            diagnostic(diagnostics, "screen snapshot " .. field .. "[" .. index .. "] must be a string")
            valid = false
        elseif #line > MAX_LINE_LENGTH then
            diagnostic(diagnostics, "screen snapshot " .. field .. "[" .. index .. "] is too long")
            valid = false
        else
            bytes = bytes + #line
            if bytes > MAX_TOTAL_LINE_BYTES then
                diagnostic(diagnostics, "screen snapshot " .. field .. " is too large")
                return false
            end
        end
    end
    if count ~= #value then
        diagnostic(diagnostics, "screen snapshot " .. field .. " has an invalid line list")
        valid = false
    end
    return valid
end

local function line_list(value)
    if type(value) ~= "table" then return nil end
    local result = {}
    for index, line in ipairs(value) do
        if index > MAX_LINES then break end
        result[#result + 1] = clean(line)
    end
    return result
end

local function non_empty(lines)
    local result = {}
    for _, line in ipairs(lines or {}) do
        if line:match("%S") then result[#result + 1] = line end
    end
    return result
end

local function starts_with_prompt(line)
    line = line:gsub("^%s+", "")
    if line:sub(1, #"❯") == "❯" then return "❯" end
    if line:sub(1, #"›") == "›" then return "›" end
end

local function screen_regions(screen)
    local recent = line_list(screen.recent_lines) or line_list(screen.bottom_lines) or {}
    local bottom = line_list(screen.bottom_lines) or non_empty(recent)
    local top = line_list(screen.top_lines) or {}
    local current_supplied = screen.current_prompt_lines ~= nil
    local current = line_list(screen.current_prompt_lines)
    local marker_index, marker
    for index, line in ipairs(recent) do
        local found = starts_with_prompt(line)
        if found then marker_index, marker = index, found end
    end

    if not current_supplied then
        current = {}
        if marker_index then
            local marker_line = recent[marker_index]:gsub("^%s+", "")
            local rest = marker_line:sub(#marker + 1):gsub("^%s+", "")
            if rest ~= "" then current[#current + 1] = rest end
            for index = marker_index + 1, #recent do current[#current + 1] = recent[index] end
        end
    end

    local before = line_list(screen.before_current_prompt_lines)
    if not before then
        before = {}
        if marker_index then
            for index = 1, marker_index - 1 do before[#before + 1] = recent[index] end
        else
            for _, line in ipairs(recent) do before[#before + 1] = line end
        end
    end

    -- An empty prompt still has useful, visible evidence for idle rules.
    if #current == 0 and marker then current[#current + 1] = marker end
    return {
        current_prompt = current,
        before_current_prompt = before,
        bottom_non_empty = non_empty(bottom),
        recent = recent,
        top_non_empty = non_empty(top),
        osc_title = screen.osc_title and { clean(screen.osc_title) } or {},
    }
end

local function evidence_add(result, lines)
    for _, line in ipairs(lines or {}) do
        if #result >= MAX_EVIDENCE_LINES then break end
        local value = truncate(clean(line), MAX_EVIDENCE_LENGTH)
        if value ~= "" then
            local duplicate = false
            for _, previous in ipairs(result) do
                if previous == value then duplicate = true break end
            end
            if not duplicate then result[#result + 1] = value end
        end
    end
end

local function matching_lines(lines, matcher, case_sensitive)
    local result = {}
    local text = table.concat(lines, "\n")
    local compare_text = case_sensitive and text or text:lower()
    local function add_if(predicate)
        if not predicate(compare_text) then return false end
        for _, line in ipairs(lines) do
            local compare_line = case_sensitive and line or line:lower()
            if predicate(compare_line) then result[#result + 1] = line end
        end
        if #result == 0 then evidence_add(result, lines) end
        return true
    end

    if matcher.contains then
        local needle = case_sensitive and matcher.contains or matcher.contains:lower()
        return add_if(function(value) return value:find(needle, 1, true) ~= nil end), result
    elseif matcher.contains_any then
        local values = {}
        for _, value in ipairs(matcher.contains_any) do values[#values + 1] = case_sensitive and value or value:lower() end
        return add_if(function(value)
            for _, needle in ipairs(values) do
                if value:find(needle, 1, true) then return true end
            end
            return false
        end), result
    elseif matcher.regex then
        local pattern = case_sensitive and matcher.regex or matcher.regex:lower()
        local ok, found = pcall(string.find, compare_text, pattern)
        if not ok or not found then return false, result end
        for _, line in ipairs(lines) do
            local compare_line = case_sensitive and line or line:lower()
            local line_ok, line_found = pcall(string.find, compare_line, pattern)
            if line_ok and line_found then result[#result + 1] = line end
        end
        if #result == 0 then evidence_add(result, lines) end
        return true, result
    end
    return nil, result
end

local function evaluate(matcher, lines, case_sensitive, depth)
    if depth > MAX_MATCHER_DEPTH then return false, {} end
    if matcher.contains or matcher.contains_any or matcher.regex then
        return matching_lines(lines, matcher, case_sensitive)
    end
    if matcher.any then
        local evidence = {}
        for _, child in ipairs(matcher.any) do
            local matched, child_evidence = evaluate(child, lines, case_sensitive, depth + 1)
            if matched then
                evidence_add(evidence, child_evidence)
                return true, evidence
            end
        end
        return false, evidence
    end
    if matcher.all then
        local evidence = {}
        for _, child in ipairs(matcher.all) do
            local matched, child_evidence = evaluate(child, lines, case_sensitive, depth + 1)
            if not matched then return false, evidence end
            evidence_add(evidence, child_evidence)
        end
        return true, evidence
    end
    if matcher["not"] then
        local matched
        if is_array(matcher["not"]) then
            matched = false
            for _, child in ipairs(matcher["not"]) do
                local child_matched = evaluate(child, lines, case_sensitive, depth + 1)
                if child_matched then matched = true break end
            end
        else
            matched = evaluate(matcher["not"], lines, case_sensitive, depth + 1)
        end
        return not matched, matched and {} or { lines[1] }
    end
    return false, {}
end

local function validate_manifest(manifest, diagnostics)
    if type(manifest) ~= "table" then
        diagnostic(diagnostics, "manifest must be a table")
        return false
    end
    if type(manifest.version) ~= "number" or manifest.version % 1 ~= 0 or manifest.version < 1 then
        diagnostic(diagnostics, "manifest version must be a positive integer")
        return false
    end
    if type(manifest.default) ~= "string"
        or manifest.default == ""
        or #manifest.default > MAX_STATUS_LENGTH
    then
        diagnostic(diagnostics, "manifest default must be a bounded non-empty string")
        return false
    end
    if type(manifest.rules) ~= "table" then
        diagnostic(diagnostics, "manifest rules must be a table")
        return false
    end
    return true
end

local function valid_rules(manifest, diagnostics)
    local result = {}
    local rule_count = 0
    for index, rule in ipairs(manifest.rules) do
        rule_count = rule_count + 1
        if rule_count > MAX_RULES then
            diagnostic(diagnostics, "manifest has too many rules; remaining rules skipped")
            break
        end
        local path = "rule[" .. index .. "]"
        local valid, err = true, nil
        if type(rule) ~= "table" then
            valid, err = false, "must be a table"
        else
            local allowed = {
                id = true,
                state = true,
                priority = true,
                region = true,
                skip_state_update = true,
                case_sensitive = true,
                evidence = true,
                contains = true,
                contains_any = true,
                regex = true,
                any = true,
                all = true,
                ["not"] = true,
            }
            for key in pairs(rule) do
                if not allowed[key] then
                    valid, err = false, "unknown field " .. tostring(key)
                    break
                end
            end
        end
        if valid then
            if type(rule.id) ~= "string" or rule.id == "" or #rule.id > MAX_STATUS_LENGTH then
                valid, err = false, "id must be a bounded non-empty string"
            elseif type(rule.state) ~= "string" or rule.state == "" or #rule.state > MAX_STATUS_LENGTH then
                valid, err = false, "state must be a bounded non-empty string"
            elseif type(rule.priority) ~= "number" then
                valid, err = false, "priority must be a number"
            elseif type(rule.region) ~= "string" or not regions[rule.region] then
                valid, err = false, "region is unsupported"
            elseif rule.skip_state_update ~= nil and type(rule.skip_state_update) ~= "boolean" then
                valid, err = false, "skip_state_update must be boolean"
            elseif rule.case_sensitive ~= nil and type(rule.case_sensitive) ~= "boolean" then
                valid, err = false, "case_sensitive must be boolean"
            elseif rule.evidence ~= nil and type(rule.evidence) ~= "boolean" then
                valid, err = false, "evidence must be boolean"
            else
                local matcher = {}
                for _, key in ipairs({ "contains", "contains_any", "regex", "any", "all", "not" }) do
                    if rule[key] ~= nil then matcher[key] = rule[key] end
                end
                valid, err = validate_matcher(matcher, path, 0)
            end
        end
        if valid then
            result[#result + 1] = { rule = rule, index = index }
        else
            diagnostic(diagnostics, path .. " skipped: " .. tostring(err))
        end
    end
    table.sort(result, function(left, right)
        if left.rule.priority == right.rule.priority then return left.index < right.index end
        return left.rule.priority > right.rule.priority
    end)
    return result
end

local function result_base(state, source, manifest_id, manifest, diagnostics)
    return {
        state = state,
        source = source,
        rule_id = nil,
        manifest_id = manifest_id,
        manifest_version = manifest and manifest.version or nil,
        evidence = {},
        skip_state_update = false,
        diagnostics = diagnostics,
    }
end

---@param input table
---@return table
function M.observe(input)
    local diagnostics = {}
    if type(input) ~= "table" then
        diagnostic(diagnostics, "observation input must be a table")
        return result_base("unknown", "unknown", nil, nil, diagnostics)
    end

    local name = input.name
    if name ~= nil and (type(name) ~= "string" or #name > MAX_STATUS_LENGTH) then
        diagnostic(diagnostics, "observation agent name must be a bounded string")
        return result_base("unknown", "unknown", nil, nil, diagnostics)
    end
    local manifest = input.manifest
    if type(manifest) == "string" then manifest = manifests[manifest] end
    if manifest == nil and type(name) == "string" then manifest = manifests[name] end
    local manifest_id = (type(manifest) == "table" and manifest.id) or name
    if type(manifest_id) ~= "string" or manifest_id == "" or #manifest_id > MAX_STATUS_LENGTH then
        diagnostic(diagnostics, "observation agent name is required and bounded")
        return result_base("unknown", "unknown", manifest_id, nil, diagnostics)
    end
    if not validate_manifest(manifest, diagnostics) then
        return result_base("unknown", "unknown", manifest_id, nil, diagnostics)
    end

    local screen = input.screen
    if type(screen) ~= "table" then
        diagnostic(diagnostics, "screen snapshot is required")
        return result_base("unknown", "unknown", manifest_id, manifest, diagnostics)
    end
    local total_line_bytes = 0
    for _, field in ipairs({
        "bottom_lines",
        "recent_lines",
        "current_prompt_lines",
        "before_current_prompt_lines",
        "top_lines",
    }) do
        if not validate_line_list(screen[field], field, diagnostics) then
            return result_base("unknown", "unknown", manifest_id, manifest, diagnostics)
        end
        for _, line in pairs(screen[field] or {}) do
            total_line_bytes = total_line_bytes + #line
            if total_line_bytes > MAX_TOTAL_LINE_BYTES then
                diagnostic(diagnostics, "screen snapshot is too large")
                return result_base("unknown", "unknown", manifest_id, manifest, diagnostics)
            end
        end
    end
    if screen.osc_title ~= nil
        and (type(screen.osc_title) ~= "string" or #screen.osc_title > MAX_LINE_LENGTH)
    then
        diagnostic(diagnostics, "screen snapshot osc_title must be a bounded string")
        return result_base("unknown", "unknown", manifest_id, manifest, diagnostics)
    end
    if screen.error ~= nil and (type(screen.error) ~= "string" or #screen.error > MAX_LINE_LENGTH) then
        diagnostic(diagnostics, "screen snapshot error must be a bounded string")
        return result_base("unknown", "unknown", manifest_id, manifest, diagnostics)
    end
    if screen.complete ~= nil and type(screen.complete) ~= "boolean" then
        diagnostic(diagnostics, "screen snapshot complete must be a boolean")
        return result_base("unknown", "unknown", manifest_id, manifest, diagnostics)
    end
    if screen.complete == false then
        diagnostic(diagnostics, "screen snapshot is incomplete" .. (screen.error and ": " .. clean(screen.error) or ""))
        return result_base("unknown", "unknown", manifest_id, manifest, diagnostics)
    end

    local available = screen_regions(screen)
    for _, entry in ipairs(valid_rules(manifest, diagnostics)) do
        local rule = entry.rule
        local matched, evidence = evaluate(rule, available[rule.region], rule.case_sensitive == true, 0)
        if matched then
            local result = result_base(rule.state, "screen", manifest_id, manifest, diagnostics)
            result.rule_id = rule.id
            result.evidence = {}
            if rule.evidence ~= false then evidence_add(result.evidence, evidence) end
            result.skip_state_update = rule.skip_state_update == true
            return result
        end
    end

    local result = result_base(manifest.default, "fallback", manifest_id, manifest, diagnostics)
    return result
end

-- Compatibility facade for the existing detector. New callers should pass a
-- structured terminal snapshot to observe; this keeps the old string API and
-- its treatment of a flat recent-lines list intact.
---@param lines string[]
---@param name string?
---@return string
function M.classify(lines, name)
    if type(lines) ~= "table" then return "unknown" end
    local observation = M.observe({
        name = name,
        screen = {
            complete = true,
            bottom_lines = lines,
            recent_lines = lines,
            current_prompt_lines = lines,
        },
    })
    return observation.state
end

return M
