-- Temporary native help only; action targeting and pending state stay in sidebar.
local M = {}
local popup
local help_ns = vim.api.nvim_create_namespace("sess_sidebar_help")

local actions = {
    { "<CR>", "Load session, then focus selected/remembered agent", "row" },
    { "<Tab>", "Toggle parent session expansion", "row" },
    { "<S-Tab>", "Collapse all if any expanded; otherwise expand all" },
    { "<C-j> / <C-k>", "Next / previous session header" },
    { "r / <C-r>", "Refresh" },
    { "rr", "Rename session", "row" },
    { "uu", "Safely unload session (Save/Discard/Cancel; Stop/Cancel)", "row" },
    { "dd", "Delete stored session (confirmation)", "row" },
    { "<C-b>", "Assign mark (a-z, 0-9)", "row" },
    { "um", "Clear assigned mark (no-op if none)", "clear" },
    { "p", "Toggle pin", "row" },
    { "<C-y>", "Copy full session cwd to + register", "row" },
    { "<C-o>", "Focus agent WITHOUT switching sessions", "focus" },
    { "<C-s>", "Sort: default > recent > pinned > activity > name" },
    { "?", "Open this help" },
    { "q / <Esc>", "Close sidebar (in help: dismiss help)" },
}

local function restore_origin(current)
    if
        vim.api.nvim_get_current_tabpage() == current.origin_tab
        and vim.api.nvim_win_is_valid(current.origin)
    then
        pcall(vim.api.nvim_set_current_win, current.origin)
    end
end

function M.close()
    local current = popup
    if not current then
        return true
    end
    local caller = vim.api.nvim_get_current_win()
    local restore = vim.api.nvim_get_current_tabpage() == current.origin_tab
    current.closing = true
    if vim.api.nvim_win_is_valid(current.win) then
        local ok, closed = pcall(vim.api.nvim_win_close, current.win, true)
        if not ok or closed == false then
            current.closing = false
            return false
        end
    end
    popup = nil
    -- :tabnew can briefly display this scratch buffer in its new content
    -- window during TabEnter. Do not delete that window/tab underneath it;
    -- bufhidden=wipe cleans the buffer when the command replaces it.
    if vim.api.nvim_buf_is_valid(current.buf) and #vim.fn.win_findbuf(current.buf) == 0 then
        pcall(vim.api.nvim_buf_delete, current.buf, { force = true })
    end
    if restore then
        restore_origin(current)
    elseif vim.api.nvim_win_is_valid(caller) then
        pcall(vim.api.nvim_set_current_win, caller)
    end
    return true
end

function M.show(context)
    if not M.close() then
        return false
    end
    local origin = vim.api.nvim_get_current_win()
    local origin_tab = vim.api.nvim_get_current_tabpage()
    local lines = {
        "SESS SIDEBAR ACTIONS",
        "Session actions on agent rows target their parent session.",
        "j/k, <C-f>/<C-b> scroll help; q/<Esc> dismiss.",
        "",
    }
    local available, unavailable, groups_by_reason = {}, {}, {}
    local function add_action(action, reason)
        if not reason then
            available[#available + 1] = action
            return
        end
        local group = groups_by_reason[reason]
        if not group then
            group = { reason = reason, actions = {} }
            groups_by_reason[reason] = group
            unavailable[#unavailable + 1] = group
        end
        group.actions[#group.actions + 1] = action
    end
    for _, action in ipairs(actions) do
        local reason
        if action[3] == "row" then
            reason = context.row_reason
        elseif action[3] == "focus" then
            reason = context.focus_reason
        elseif action[3] == "clear" then
            reason = context.clear_reason
        end
        if context.busy and action[1] ~= "?" and action[1] ~= "q / <Esc>" then
            reason = "action/refresh in progress"
        end
        add_action(action, reason)
    end
    local mouse_reason = not context.mouse and "mouse actions are disabled" or nil
    add_action({ "<LeftMouse>", "Select row" }, mouse_reason)
    add_action({ "<2-LeftMouse>", "Accept row" }, mouse_reason)

    local available_title = #lines
    lines[#lines + 1] = "AVAILABLE"
    for _, action in ipairs(available) do
        lines[#lines + 1] = string.format("  %-16s %s", action[1], action[2])
    end
    local unavailable_title
    if #unavailable > 0 then
        lines[#lines + 1] = ""
        unavailable_title = #lines
        lines[#lines + 1] = "UNAVAILABLE"
        for index, group in ipairs(unavailable) do
            if index > 1 then
                lines[#lines + 1] = ""
            end
            lines[#lines + 1] = "  ▸ " .. group.reason
            for _, action in ipairs(group.actions) do
                lines[#lines + 1] = string.format("    %-16s %s", action[1], action[2])
            end
        end
    end
    local buf = vim.api.nvim_create_buf(false, true)
    local initialized, init_err = pcall(function()
        vim.b[buf].sess_transient_ui = true
        vim.bo[buf].buftype = "nofile"
        vim.bo[buf].bufhidden = "wipe"
        vim.bo[buf].swapfile = false
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
        vim.api.nvim_buf_add_highlight(buf, help_ns, "Title", available_title, 0, -1)
        if unavailable_title then
            vim.api.nvim_buf_add_highlight(buf, help_ns, "Title", unavailable_title, 0, -1)
            for row = unavailable_title + 1, #lines - 1 do
                vim.api.nvim_buf_add_highlight(buf, help_ns, "Comment", row, 0, -1)
            end
        end
        vim.bo[buf].modifiable = false
    end)
    if not initialized then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        require("sess.log").error("sidebar help: " .. tostring(init_err))
        return false
    end
    local width = math.max(1, math.min(78, vim.o.columns - 4))
    local height = math.max(1, math.min(#lines, vim.o.lines - vim.o.cmdheight - 4))
    local ok, win = pcall(vim.api.nvim_open_win, buf, true, {
        relative = "editor",
        row = 1,
        col = math.max(0, math.floor((vim.o.columns - width) / 2) - 1),
        width = width,
        height = height,
        style = "minimal",
        border = "single",
    })
    if not ok then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        require("sess.log").error("sidebar help: " .. tostring(win))
        return false
    end
    popup = { win = win, buf = buf, origin = origin, origin_tab = origin_tab }
    local installed, install_err = pcall(function()
        vim.wo[win].wrap = true
        for _, key in ipairs({ "q", "<Esc>" }) do
            vim.keymap.set("n", key, M.close, { buffer = buf, silent = true, nowait = true })
        end
        vim.api.nvim_create_autocmd("WinClosed", {
            pattern = tostring(win),
            once = true,
            callback = function()
                -- External closes also wipe the scratch buffer; don't retain stale ownership.
                if popup and popup.win == win then
                    local current = popup
                    popup = nil
                    if not current.closing then
                        restore_origin(current)
                    end
                end
            end,
        })
    end)
    if not installed then
        M.close()
        require("sess.log").error("sidebar help: " .. tostring(install_err))
        return false
    end
    return true
end

return M
