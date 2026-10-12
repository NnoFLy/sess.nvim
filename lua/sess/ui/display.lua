local icons = require("sess.ui.icons")

local M = {}

local function display_width(value)
    return vim.fn.strdisplaywidth(value or "")
end

M.display_width = display_width

function M.truncate_end(value, width, ellipsis)
    value = value or ""
    ellipsis = ellipsis or icons.ellipsis
    if width == nil or display_width(value) <= width then
        return value
    elseif width <= 0 then
        return ""
    elseif width == 1 then
        return ellipsis
    end

    local chars = vim.fn.strchars(value)
    local keep = chars
    local target = width - 1
    while keep > 0 and display_width(vim.fn.strcharpart(value, 0, keep)) > target do
        keep = keep - 1
    end
    return vim.fn.strcharpart(value, 0, keep) .. ellipsis
end

function M.truncate_middle(value, width, ellipsis)
    value = value or ""
    ellipsis = ellipsis or icons.ellipsis
    if width == nil or display_width(value) <= width then
        return value
    elseif width <= 0 then
        return ""
    elseif width == 1 then
        return ellipsis
    end

    local chars = vim.fn.strchars(value)
    local left_width = math.floor((width - 1) / 2)
    local right_width = width - 1 - left_width
    local left_chars = chars
    while left_chars > 0
        and display_width(vim.fn.strcharpart(value, 0, left_chars)) > left_width
    do
        left_chars = left_chars - 1
    end
    local right_chars = chars
    while right_chars > 0
        and display_width(vim.fn.strcharpart(value, chars - right_chars, right_chars)) > right_width
    do
        right_chars = right_chars - 1
    end

    return vim.fn.strcharpart(value, 0, left_chars)
        .. ellipsis
        .. vim.fn.strcharpart(value, chars - right_chars, right_chars)
end

local function part_width(part)
    return display_width(part.text or "")
end

local function total_width(parts)
    local width = 0
    for _, part in ipairs(parts) do
        width = width + part_width(part)
    end
    return width
end

local function sorted_indices(parts, field)
    local indices = {}
    for index, part in ipairs(parts) do
        if part[field] ~= nil then
            indices[#indices + 1] = index
        end
    end
    table.sort(indices, function(left, right)
        local a, b = parts[left][field], parts[right][field]
        if a == b then
            return left < right
        end
        return a > b
    end)
    return indices
end

--- Fit logical display segments without mutating their source values.
---@param parts table[]
---@param width number?
---@return table[]
function M.fit_parts(parts, width)
    local fitted = vim.deepcopy(parts or {})
    if width == nil then
        return fitted
    end
    width = math.max(0, math.floor(width))

    local deficit = total_width(fitted) - width
    if deficit > 0 then
        local expendable = {}
        for index, part in ipairs(fitted) do
            if part.expendable and part.shrink_priority ~= nil then
                expendable[#expendable + 1] = index
            end
        end
        table.sort(expendable, function(left, right)
            local a, b = fitted[left].shrink_priority, fitted[right].shrink_priority
            return a == b and left < right or a < b
        end)
        for _, index in ipairs(expendable) do
            if deficit <= 0 then
                break
            end
            local part = fitted[index]
            local current = part_width(part)
            local minimum = math.max(0, part.min_width or 0)
            if current > minimum then
                local target = math.max(minimum, current - deficit)
                local truncate = part.truncate == "middle" and M.truncate_middle or M.truncate_end
                part.text = truncate(part.text or "", target, part.ellipsis)
                deficit = total_width(fitted) - width
            end
        end
    end

    if deficit > 0 then
        for _, index in ipairs(sorted_indices(fitted, "omit_priority")) do
            if deficit <= 0 then
                break
            end
            fitted[index].text = ""
            deficit = total_width(fitted) - width
        end
    end

    if deficit > 0 then
        local indices = {}
        for index, part in ipairs(fitted) do
            if part.shrink_priority ~= nil then
                indices[#indices + 1] = index
            end
        end
        table.sort(indices, function(left, right)
            local a, b = fitted[left].shrink_priority, fitted[right].shrink_priority
            return a == b and left < right or a < b
        end)
        for _, index in ipairs(indices) do
            if deficit <= 0 then
                break
            end
            local part = fitted[index]
            local current = part_width(part)
            local minimum = math.max(0, part.min_width or 0)
            if current > minimum then
                local target = math.max(minimum, current - deficit)
                local truncate = part.truncate == "middle" and M.truncate_middle or M.truncate_end
                part.text = truncate(part.text or "", target, part.ellipsis)
                deficit = total_width(fitted) - width
            end
        end
    end

    if deficit > 0 then
        for index = #fitted, 1, -1 do
            if deficit <= 0 then
                break
            end
            local part = fitted[index]
            local current = part_width(part)
            if current > 0 then
                part.text = M.truncate_end(part.text or "", math.max(0, current - deficit), part.ellipsis)
                deficit = total_width(fitted) - width
            end
        end
    end
    return fitted
end

return M
