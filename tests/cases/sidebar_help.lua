fixture.setup()
local help = require("sess.ui.sidebar_help")
local origin = vim.api.nvim_get_current_win()
local ns = vim.api.nvim_get_namespaces().sess_sidebar_help

local function show(context)
    assert(help.show(context))
    local buf = vim.api.nvim_get_current_buf()
    return vim.api.nvim_buf_get_lines(buf, 0, -1, false), buf
end

local function find(lines, text, exact)
    local found
    for index, line in ipairs(lines) do
        if (exact and line == text) or (not exact and line:find(text, 1, true)) then
            assert(not found, "repeated help text: " .. text)
            found = index
        end
    end
    assert(found, "missing help text: " .. text)
    return found
end

local function highlighted(buf, index, group)
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
        if mark[2] == index - 1 and mark[4].hl_group == group then
            return true
        end
    end
    return false
end

-- Shared restrictions appear once, below available shortcuts; each shortcut
-- remains discoverable and unavailable entries use the theme's dim text.
local row_reason = "cursor is not on a session/agent row"
local lines, buf = show({
    row_reason = row_reason,
    clear_reason = row_reason,
    focus_reason = row_reason,
    mouse = false,
})
local available = find(lines, "AVAILABLE", true)
local unavailable = find(lines, "UNAVAILABLE", true)
local row_heading = find(lines, "  ▸ " .. row_reason, true)
local mouse_heading = find(lines, "  ▸ mouse actions are disabled", true)
assert(available < find(lines, "Refresh") and find(lines, "Refresh") < unavailable)
assert(unavailable < row_heading and row_heading < find(lines, "<CR>"))
assert(find(lines, "<C-o>") < mouse_heading)
assert(mouse_heading < find(lines, "<LeftMouse>"))
assert(mouse_heading < find(lines, "<2-LeftMouse>"))
find(lines, row_reason) -- no duplicate reason under individual actions
assert(highlighted(buf, available, "Title"))
assert(highlighted(buf, unavailable, "Title"))
for index = unavailable + 1, #lines do
    if lines[index] ~= "" then
        assert(highlighted(buf, index, "Comment"), lines[index])
    end
end
assert(not highlighted(buf, find(lines, "Refresh"), "Comment"))
assert(help.close())
fixture.equal(origin, vim.api.nvim_get_current_win())

-- Distinct restrictions stay attached to their own group; available actions
-- retain their catalog order rather than being sorted by key or reason.
lines = show({
    clear_reason = "session has no mark",
    focus_reason = "agent session is not current",
    mouse = true,
})
unavailable = find(lines, "UNAVAILABLE", true)
assert(find(lines, "<CR>") < find(lines, "<Tab>"))
assert(find(lines, "<2-LeftMouse>") < unavailable)
assert(unavailable < find(lines, "  ▸ session has no mark", true))
assert(find(lines, "session has no mark") < find(lines, "um"))
assert(find(lines, "um") < find(lines, "agent session is not current"))
assert(find(lines, "agent session is not current") < find(lines, "<C-o>"))
assert(help.close())

-- Pending state overrides row/mark/focus restrictions with one shared reason.
lines = show({ busy = true, row_reason = row_reason, mouse = true })
unavailable = find(lines, "UNAVAILABLE", true)
local busy_heading = find(lines, "  ▸ action/refresh in progress", true)
assert(find(lines, "Open this help") < unavailable)
assert(find(lines, "Close sidebar") < unavailable)
assert(unavailable < busy_heading and busy_heading < find(lines, "Refresh"))
find(lines, "action/refresh in progress")
assert(not table.concat(lines, "\n"):find(row_reason, 1, true))
assert(help.close())

-- No empty unavailable section when every action is available.
lines = show({ mouse = true })
assert(not vim.list_contains(lines, "UNAVAILABLE"))
assert(help.close())

-- Narrow editors retain complete, wrapped text and a scrollable help window.
local columns, height = vim.o.columns, vim.o.lines
vim.o.columns, vim.o.lines = 40, 12
lines, buf = show({ row_reason = row_reason, mouse = false })
local win = vim.api.nvim_get_current_win()
assert(vim.api.nvim_win_get_width(win) <= 36)
assert(vim.wo[win].wrap)
assert(vim.api.nvim_win_get_height(win) < #lines)
find(lines, "Load session, then focus selected/remembered agent")
vim.cmd("normal! G")
fixture.equal(#lines, vim.api.nvim_win_get_cursor(win)[1])
vim.fn.maparg("q", "n", false, true).callback()
assert(not vim.api.nvim_buf_is_valid(buf))
fixture.equal(origin, vim.api.nvim_get_current_win())
vim.o.columns, vim.o.lines = columns, height
