-- Default symbols used by the Sess Telescope UI.
local symbols = {
    ellipsis = "…",
    separator = "·",
    focus = ">",
    status = {
        blocked = "⚠",
        done = "✓",
        idle = "○",
        unknown = "?",
        working = "●",
    },
    state = {
        new = "+",
        current = "●",
        active = "○",
        inactive = "·",
    },
    metadata = {
        pinned = "★",
        previous = "◆",
    },
    tree = {
        expanded = "▾ ",
        collapsed = "▸ ",
        branch = "├─",
        last_branch = "└─",
        empty = "└─ ",
    },
}

local ascii_symbols = {
    ellipsis = ".",
    separator = "|",
    focus = ">",
    status = {
        blocked = "!",
        done = "x",
        idle = "o",
        unknown = "?",
        working = "*",
    },
    state = {
        new = "+",
        current = "*",
        active = "o",
        inactive = ".",
    },
    metadata = {
        pinned = "*",
        previous = "<",
    },
    tree = {
        expanded = "v ",
        collapsed = "> ",
        branch = "|-",
        last_branch = "`-",
        empty = "`- ",
    },
}

local M = vim.deepcopy(symbols)

---@param options table?
---@return table
function M.for_display(options)
    options = options or {}
    if options.icons == false or options.ascii_fallback == true then
        return vim.deepcopy(ascii_symbols)
    end
    return vim.deepcopy(symbols)
end

return M
