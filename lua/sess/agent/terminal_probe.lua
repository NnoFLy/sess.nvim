local M = {}

local MAX_READ_LINES = 200
local MAX_TOP_LINES = 25
local MAX_BOTTOM_LINES = 25
local MAX_CURRENT_PROMPT_LINES = 25
local MAX_LINE_LENGTH = 1000
local MAX_TITLE_LENGTH = 200

local normalized

local function truncate(value, limit)
    if #value <= limit then return value end
    local result = value:sub(1, limit)
    -- Do not leave a partial UTF-8 sequence in the diagnostic or evidence.
    while #result > 0 and result:byte(-1) >= 128 and result:byte(-1) <= 191 do
        result = result:sub(1, -2)
    end
    return result
end

local function clean_title(value)
    return truncate(normalized(value), MAX_TITLE_LENGTH)
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
    local first = value:byte(lead)
    local width
    if first and first >= 194 and first <= 223 then
        width = 2
    elseif first and first >= 224 and first <= 239 then
        width = 3
    elseif first and first >= 240 and first <= 244 then
        width = 4
    else
        return false
    end
    local offset = index - lead
    return offset > 0 and offset < width
end

local function osc_end(value, start)
    local index = start
    while index <= #value do
        local byte = value:byte(index)
        if byte == 7 or byte == 156 then -- BEL or C1 ST
            return index, value:sub(start, index - 1), true
        elseif byte == 27 and value:byte(index + 1) == 92 then -- ST (ESC \\)
            return index + 1, value:sub(start, index - 1), true
        end
        index = index + 1
    end
    return #value, nil, false
end

local function capture_title(payload, on_title)
    local title = payload:match("^[02];(.*)$")
    if title and on_title then on_title(clean_title(title)) end
end

normalized = function(value, on_title)
    value = value:gsub("\r", "")
    local result = {}
    local index = 1
    while index <= #value do
        local byte = value:byte(index)
        if byte == 27 or (byte == 155 and not utf8_continuation(value, index)) then
            local introducer = value:byte(index + 1)
            local csi = byte == 155 or introducer == 91
            if csi then
                local cursor = byte == 155 and index + 1 or index + 2
                while cursor <= #value do
                    local final = value:byte(cursor)
                    if final >= 64 and final <= 126 then
                        cursor = cursor + 1
                        break
                    end
                    cursor = cursor + 1
                end
                -- An unterminated control sequence is discarded, rather than
                -- allowing arbitrary terminal data into the observation.
                index = cursor
            elseif introducer == 93 then
                local finish, payload, complete = osc_end(value, index + 2)
                if complete and payload then
                    capture_title(payload, on_title)
                    index = finish + 1
                else
                    index = #value + 1
                end
            else
                -- Drop an unknown two-byte ESC sequence. It is not input and
                -- must not become visible evidence merely because it is unknown.
                index = math.min(#value + 1, index + 2)
            end
        elseif byte == 157 and not utf8_continuation(value, index) then -- C1 OSC
            local finish, payload, complete = osc_end(value, index + 1)
            if complete and payload then
                capture_title(payload, on_title)
                index = finish + 1
            else
                index = #value + 1
            end
        elseif byte < 32 or (byte >= 127 and byte <= 159 and not utf8_continuation(value, index)) then
            -- Keep ordinary text and tabs, but remove terminal controls such as
            -- BEL and backspace even when they are not part of an ANSI sequence.
            -- UTF-8 continuation bytes overlap the C1 control range, so retain
            -- them when they follow a non-ASCII lead byte.
            if byte == 9 then result[#result + 1] = "\t" end
            index = index + 1
        else
            result[#result + 1] = string.char(byte)
            index = index + 1
        end
    end
    return truncate(table.concat(result), MAX_LINE_LENGTH)
end

local function is_blank(value)
    return value:match("^%s*$") ~= nil
end

local function trim_trailing_blank(lines)
    local last = #lines
    while last > 0 and is_blank(lines[last]) do last = last - 1 end
    return last
end

local function non_empty_slice(lines, first, last, limit)
    local result = {}
    for index = first, last do
        if not is_blank(lines[index]) then
            result[#result + 1] = lines[index]
            if #result == limit then break end
        end
    end
    return result
end

local function failed_snapshot(bufnr, changedtick, message)
    return {
        bufnr = bufnr,
        changedtick = changedtick,
        bottom_lines = {},
        recent_lines = {},
        current_prompt_lines = {},
        top_lines = {},
        osc_title = nil,
        complete = false,
        error = truncate(normalized(tostring(message)), MAX_LINE_LENGTH),
    }
end

function M.job_id(bufnr)
    local ok, value = pcall(function() return vim.b[bufnr].terminal_job_id end)
    return ok and value or nil
end

function M.job_alive(bufnr)
    local job_id = M.job_id(bufnr)
    if type(job_id) ~= "number" or job_id % 1 ~= 0 or job_id < 1 then return false end

    -- Some supported Neovim versions do not expose job_info(). In that case
    -- retain the existing best-effort terminal behavior; when it is available,
    -- an exited job must not be treated as a live terminal target.
    if type(vim.fn.job_info) ~= "function" then return true end
    local ok, info = pcall(vim.fn.job_info, job_id)
    if not ok then
        -- `job_info` is absent on older supported Neovim versions. Fall back
        -- to the non-blocking jobwait API there; an unknown job id remains
        -- best-effort so legacy injected probes keep working.
        if tostring(info):find("Unknown function", 1, true) then
            local wait_ok, result = pcall(vim.fn.jobwait, { job_id }, 0)
            local code = wait_ok and type(result) == "table" and result[1] or nil
            if code == -1 or code == -2 then return true end
            if type(code) == "number" and code >= 0 then return false end
            return true
        end
        return false
    end
    if type(info) ~= "table" then return false end
    return info.status == "run" or info.status == "running"
end

function M.name(bufnr)
    local ok, value = pcall(vim.api.nvim_buf_get_name, bufnr)
    if not ok or type(value) ~= "string" then return nil end
    return value:match("([^:]+)$")
end

function M.changedtick(bufnr)
    local ok, value = pcall(vim.api.nvim_buf_get_changedtick, bufnr)
    return ok and value or nil
end

---@param bufnr integer
---@return Sess.AgentScreen
function M.snapshot(bufnr)
    local tick = M.changedtick(bufnr)
    local ok, count = pcall(vim.api.nvim_buf_line_count, bufnr)
    if not ok then return failed_snapshot(bufnr, tick, count) end

    local function read(first, last)
        local read_ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, first, last, false)
        if not read_ok then return nil, lines end
        if type(lines) ~= "table" then return nil, "terminal buffer lines must be a table" end
        return lines
    end

    local raw_top, raw_recent
    if count <= MAX_READ_LINES then
        raw_recent, ok = read(0, count)
        if not raw_recent then return failed_snapshot(bufnr, tick, ok) end
        raw_top = raw_recent
    else
        raw_top, ok = read(0, MAX_TOP_LINES)
        if not raw_top then return failed_snapshot(bufnr, tick, ok) end
        raw_recent, ok = read(count - MAX_READ_LINES, count)
        if not raw_recent then return failed_snapshot(bufnr, tick, ok) end
    end

    local title
    local function normalize_lines(lines, field)
        local result = {}
        for index, line in ipairs(lines) do
            if type(line) ~= "string" then
                return nil, "terminal snapshot " .. field .. "[" .. index .. "] must be a string"
            end
            result[index] = normalized(line, function(value) title = value end)
        end
        return result
    end

    local top, normalize_error = normalize_lines(raw_top, "top_lines")
    if not top then return failed_snapshot(bufnr, tick, normalize_error) end
    local recent
    if raw_top == raw_recent then
        recent = top
    else
        recent, normalize_error = normalize_lines(raw_recent, "recent_lines")
        if not recent then return failed_snapshot(bufnr, tick, normalize_error) end
    end
    local last = trim_trailing_blank(recent)
    local bottom = non_empty_slice(recent, math.max(1, last - MAX_BOTTOM_LINES + 1), last, MAX_BOTTOM_LINES)
    local top_lines = non_empty_slice(top, 1, #top, MAX_TOP_LINES)

    local prompt_index, prompt_text
    for index = 1, last do
        local line = recent[index]:gsub("^%s+", "")
        local marker
        if line:sub(1, #"❯") == "❯" then
            marker = "❯"
        elseif line:sub(1, #"›") == "›" then
            marker = "›"
        end
        if marker then
            prompt_index = index
            prompt_text = line:sub(#marker + 1):gsub("^%s+", "")
        end
    end

    local current_prompt = {}
    if prompt_index then
        if prompt_text ~= "" then current_prompt[#current_prompt + 1] = prompt_text end
        for index = prompt_index + 1, last do
            current_prompt[#current_prompt + 1] = recent[index]
        end
        while #current_prompt > 0 and is_blank(current_prompt[#current_prompt]) do
            table.remove(current_prompt)
        end
        if #current_prompt > MAX_CURRENT_PROMPT_LINES then
            for index = #current_prompt, MAX_CURRENT_PROMPT_LINES + 1, -1 do current_prompt[index] = nil end
        end
    end

    return {
        bufnr = bufnr,
        changedtick = tick,
        bottom_lines = bottom,
        recent_lines = recent,
        current_prompt_lines = current_prompt,
        top_lines = top_lines,
        osc_title = title,
        complete = true,
        error = nil,
    }
end

function M.lines(bufnr)
    local snapshot = M.snapshot(bufnr)
    if not snapshot.complete then return nil end
    return snapshot.bottom_lines
end

return M
