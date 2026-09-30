local M = {}

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function contains_any(text, values)
    for _, value in ipairs(values) do
        if text:find(value, 1, true) then return true end
    end
    return false
end

local function has_input_prompt(lines)
    local line = trim(lines[#lines] or "")
    return line:sub(1, 3) == "❯" or line:sub(1, 3) == "›"
end

---@param lines string[]
---@param name string?
---@return string
function M.classify(lines, name)
    if type(lines) ~= "table" then return "unknown" end
    local text = table.concat(lines, "\n"):lower()
    if contains_any(text, {
        "action required", "allow command?", "do you want to proceed",
        "do you want to allow", "would you like to", "esc to cancel",
        "enter to confirm", "enter to select", "[y/n]", "waiting for permission",
    }) then return "blocked" end
    if contains_any(text, {
        "working...", " to interrupt", "── working ──", "⠋ working",
        "⠙ working", "⠹ working", "⠸ working", "⠼ working", "⠴ working",
        "⠦ working", "⠧ working", "⠇ working", "⠏ working",
    }) then return "working" end
    if has_input_prompt(lines) then return "idle" end
    return (name == "pi" or name == "omp") and "idle" or "unknown"
end

return M
