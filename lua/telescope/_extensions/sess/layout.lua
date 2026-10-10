local M = {}

local function display_width(value)
    return vim.fn.strdisplaywidth(value or "")
end

M.display_width = display_width

local function truncate_end(value, width)
    value = value or ""
    if width == nil or display_width(value) <= width then
        return value
    end
    if width <= 0 then
        return ""
    elseif width == 1 then
        return "…"
    end

    local chars = vim.fn.strchars(value)
    local keep = chars
    local target = width - 1
    while keep > 0 and display_width(vim.fn.strcharpart(value, 0, keep)) > target do
        keep = keep - 1
    end
    return vim.fn.strcharpart(value, 0, keep) .. "…"
end

M.truncate_end = truncate_end

local function truncate_middle(value, width)
    value = value or ""
    if width == nil or display_width(value) <= width then
        return value
    end
    if width <= 0 then
        return ""
    elseif width == 1 then
        return "…"
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
        .. "…"
        .. vim.fn.strcharpart(value, chars - right_chars, right_chars)
end

M.truncate_middle = truncate_middle

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

local function sorted_indices(parts, field, reverse)
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
        if reverse then
            return a > b
        end
        return a < b
    end)
    return indices
end

--- Fit independently highlighted display parts to a screen-cell width.
--- Parts are copied, so callers retain the complete searchable/action values.
---@param parts table[]
---@param width number?
---@return table[]
function M.fit_parts(parts, width)
    local fitted = vim.deepcopy(parts or {})
    if width == nil then
        return fitted
    end
    width = math.max(0, math.floor(width))

    -- Shrink only expendable values before dropping optional labels. Identity
    -- columns stay intact until optional content has had a chance to disappear.
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
            if a == b then
                return left < right
            end
            return a < b
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
                local truncate = part.truncate == "middle" and truncate_middle or truncate_end
                part.text = truncate(part.text or "", target)
                deficit = total_width(fitted) - width
            end
        end
    end

    -- Secondary labels are the first content to disappear. Higher omission
    -- priorities are less important; equal priorities remain deterministic.
    if deficit > 0 then
        for _, index in ipairs(sorted_indices(fitted, "omit_priority", true)) do
            if deficit <= 0 then
                break
            end
            fitted[index].text = ""
            deficit = total_width(fitted) - width
        end
    end

    -- A required value may still be too wide at the documented minimum. This
    -- final pass is intentionally deterministic and never splits characters.
    if deficit > 0 then
        for _, index in ipairs(sorted_indices(fitted, "shrink_priority", false)) do
            if deficit <= 0 then
                break
            end
            local part = fitted[index]
            local current = part_width(part)
            local minimum = math.max(0, part.min_width or 0)
            if current > minimum then
                local target = math.max(minimum, current - deficit)
                local truncate = part.truncate == "middle" and truncate_middle or truncate_end
                part.text = truncate(part.text or "", target)
                deficit = total_width(fitted) - width
            end
        end
    end

    return fitted
end

-- Telescope's result window is the useful width, not the whole terminal. The
-- fallbacks keep pure formatting helpers usable before Telescope has laid out.
function M.preview_result_width(preview_config, terminal_width, result_width)
    preview_config = preview_config or {}
    terminal_width = terminal_width or vim.o.columns
    local source_width = result_width or terminal_width
    local candidate = math.floor(source_width * (1 - (preview_config.width or 0.35)))
    return math.max(1, candidate)
end

local telescope_preview_cutoffs = {
    horizontal = 120,
    vertical = 40,
    center = 40,
    cursor = 40,
    bottom_pane = 120,
}

-- Telescope decides whether to create a preview from the layout strategy's
-- cutoff before it creates the result window. Keep the same decision available
-- to the responsive picker code, including before a picker has been mounted.
function M.preview_cutoff(picker)
    local layout_config = picker and picker.layout_config
    local strategy = picker and picker.layout_strategy
    local ok, telescope_config = pcall(require, "telescope.config")
    if not strategy and ok and telescope_config.values then
        strategy = telescope_config.values.layout_strategy
    end
    strategy = strategy or "horizontal"
    if type(layout_config) == "table" then
        local cutoff = layout_config.preview_cutoff
        if cutoff == nil and type(strategy) == "string" then
            local strategy_config = layout_config[strategy]
            cutoff = type(strategy_config) == "table" and strategy_config.preview_cutoff or nil
        end
        if cutoff ~= nil then
            return cutoff
        end
    end

    if ok and telescope_config.values then
        strategy = strategy or telescope_config.values.layout_strategy or "horizontal"
        local defaults = telescope_config.values.layout_config or {}
        local strategy_config = defaults[strategy]
        if type(strategy_config) == "table" and strategy_config.preview_cutoff ~= nil then
            return strategy_config.preview_cutoff
        end
        if defaults.preview_cutoff ~= nil then
            return defaults.preview_cutoff
        end
    end

    return telescope_preview_cutoffs[strategy or "horizontal"]
end

function M.preview_fits(preview_config, terminal_width, result_width, picker)
    preview_config = preview_config or {}
    if preview_config.enabled == false then
        return false
    end
    terminal_width = terminal_width or vim.o.columns
    local cutoff = M.preview_cutoff(picker)
    if cutoff ~= nil and terminal_width < cutoff then
        return false
    end
    if result_width ~= nil then
        return math.floor(result_width) >= (preview_config.min_width or 80)
    end
    local candidate = M.preview_result_width(preview_config, terminal_width)
    return candidate >= (preview_config.min_width or 80)
end

function M.initial_width(preview_config, picker)
    local width = vim.o.columns
    preview_config = preview_config or {}
    if M.preview_fits(preview_config, width, nil, picker) then
        width = M.preview_result_width(preview_config, width)
    end
    return math.max(1, width)
end

local function selection_caret_width(picker)
    local caret = picker and picker.selection_caret
    if caret == nil then
        local ok, telescope_config = pcall(require, "telescope.config")
        if ok and telescope_config.values then
            caret = telescope_config.values.selection_caret
        end
    end
    return display_width(caret or "")
end

function M.available_width(picker, fallback)
    local picker_layout = picker and picker.layout
    if type(picker_layout) ~= "table" then
        picker_layout = nil
    end
    local windows = {
        picker and picker.results_win,
        picker_layout and picker_layout.results and picker_layout.results.winid,
        picker_layout and picker_layout.results and picker_layout.results.win_id,
        picker_layout and picker_layout.results_win,
    }
    for _, win in ipairs(windows) do
        if type(win) == "number" and vim.api.nvim_win_is_valid(win) then
            local ok, value = pcall(vim.api.nvim_win_get_width, win)
            if ok and value > 0 then
                return math.max(0, value - selection_caret_width(picker))
            end
        end
    end
    local results = picker_layout and picker_layout.results
    if type(results) == "table" and type(results.width) == "number" and results.width > 0 then
        return math.max(0, results.width - selection_caret_width(picker))
    end
    return math.max(0, (fallback or vim.o.columns) - selection_caret_width(picker))
end

-- A previewer can remain configured on a picker when Telescope suppresses its
-- preview window due to preview_cutoff. Responsive state must distinguish the
-- configured previewer from an actually mounted preview pane.
function M.has_preview_window(picker)
    local preview = picker and picker.layout and picker.layout.preview
    if type(preview) == "table" then
        local win = preview.winid or preview.win_id
        return type(win) == "number" and vim.api.nvim_win_is_valid(win)
    end
    local win = picker and picker.preview_win
    return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

-- Reformatting is tied to the picker lifetime; no global autocmd is left behind.
function M.on_resize(picker, callback)
    if not picker or not picker.prompt_bufnr or type(callback) ~= "function" then
        return function() end
    end
    local stopped = false
    local autocmds = {}
    local function stop()
        if stopped then
            return
        end
        stopped = true
        for _, id in ipairs(autocmds) do
            pcall(vim.api.nvim_del_autocmd, id)
        end
        autocmds = {}
    end
    autocmds[#autocmds + 1] = vim.api.nvim_create_autocmd("VimResized", {
        callback = function()
            if not stopped then
                callback(M.available_width(picker))
            end
        end,
    })
    autocmds[#autocmds + 1] = vim.api.nvim_create_autocmd({ "BufHidden", "BufWipeout" }, {
        buffer = picker.prompt_bufnr,
        callback = stop,
    })
    return stop
end

return M
