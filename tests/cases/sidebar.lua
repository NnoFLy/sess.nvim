local opts = require("sess.api.opts")

local default_sidebar = opts.get().sidebar
assert(default_sidebar.enabled == true)
assert(default_sidebar.position == "left")
assert(default_sidebar.active_expand == "all")

local store = fixture.root .. "/sidebar"
local ok, err = require("sess").setup({
    store_path = store,
    smart_auto_load = "none",
    auto_save = false,
    sidebar = {
        enabled = true,
        width = 24,
        min_width = 20,
        max_width = 30,
        refresh_interval = 50,
    },
})
assert(ok, err)

local sidebar = require("sess.ui.sidebar")
local sidebar_highlights = {
    SessSidebarCurrent = "Identifier",
    SessSidebarActive = "Identifier",
    SessSidebarName = "Normal",
    SessSidebarPath = "Comment",
    SessSidebarMark = "Number",
    SessSidebarMetadata = "Comment",
    SessSidebarStale = "DiagnosticHint",
    SessSidebarAgent = "Identifier",
    SessSidebarFocused = "IncSearch",
    SessSidebarWorking = "Identifier",
    SessSidebarIdle = "Comment",
    SessSidebarBlocked = "DiagnosticWarn",
    SessSidebarDone = "DiagnosticOk",
    SessSidebarUnknown = "DiagnosticInfo",
    SessSidebarTitle = "Title",
    SessSidebarFooter = "NonText",
}
for group, link in pairs(sidebar_highlights) do
    local highlight = vim.api.nvim_get_hl(0, { name = group, link = true })
    assert(highlight.link == link, group .. " should link to " .. link)
end
assert(not sidebar.is_open())
assert(sidebar.open())
assert(sidebar.is_open())
local sidebar_buf = vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())
assert(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(sidebar_buf), ":t") == "Sess Sidebar")
assert(vim.b[sidebar_buf].sess_transient_ui)
assert(sidebar.refresh())
assert(vim.fn.maparg("<S-Tab>", "n") ~= "")

-- A failed transient suspend keeps the visible owner active and polling.
local editor = require("sess.editor")
local suspend_window = vim.api.nvim_get_current_win()
local original_win_close = vim.api.nvim_win_close
vim.api.nvim_win_close = function(win, force)
    if win == suspend_window then error("injected sidebar close failure") end
    return original_win_close(win, force)
end
local suspend_path = vim.fn.tempname()
local suspended, suspend_err = editor.write_snapshot(suspend_path)
vim.api.nvim_win_close = original_win_close
assert(not suspended)
assert(suspend_err and suspend_err:find("suspend", 1, true))
assert(sidebar.is_open())
assert(sidebar.refresh())
vim.fn.delete(suspend_path)

-- A failed transient resume must keep the logical sidebar open so a later
-- refresh can recreate its window instead of forcing a fresh sidebar state.
local failed_snapshot_path = vim.fn.tempname()
local original_cmd = vim.cmd
vim.cmd = function(command)
    if type(command) == "string" and command:match("^topleft vertical %d+split$") then
        error("injected sidebar split failure")
    end
    return original_cmd(command)
end
local resumed, resume_err = editor.write_snapshot(failed_snapshot_path)
vim.cmd = original_cmd
assert(not resumed)
assert(resume_err and resume_err:find("transient UI resume failed", 1, true))
local retried, retry_err = sidebar.refresh()
assert(retried, retry_err)
vim.fn.delete(failed_snapshot_path)

local snapshot_path = vim.fn.tempname()
local snapshot_ok, snapshot_err = require("sess.editor").write_snapshot(snapshot_path)
assert(snapshot_ok, snapshot_err)
assert(sidebar.is_open())
local snapshot = table.concat(vim.fn.readfile(snapshot_path), "\n")
assert(not snapshot:find("ACTIVE SESSIONS", 1, true))
vim.fn.delete(snapshot_path)

vim.cmd("tabnew")
assert(sidebar.is_open())
local has_tab_sidebar = false
local tab_sidebar_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.b[buf].sess_transient_ui then
        has_tab_sidebar = true
        tab_sidebar_win = win
    end
end
assert(has_tab_sidebar)
-- Following a tab must not move focus away from the new tab's content window.
assert(not vim.b[vim.api.nvim_win_get_buf(vim.api.nvim_get_current_win())].sess_transient_ui)
-- Restore the attachment if another plugin replaced the sidebar buffer.
local replacement_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(tab_sidebar_win, replacement_buf)
assert(sidebar.refresh())
assert(vim.api.nvim_win_get_buf(tab_sidebar_win) == sidebar_buf)
-- Footer lines remain within the runtime-enforced width.
vim.api.nvim_win_set_width(tab_sidebar_win, 10)
assert(sidebar.refresh())
assert(vim.api.nvim_win_get_width(tab_sidebar_win) >= 20)
vim.wait(100)
local sidebar_width = vim.api.nvim_win_get_width(tab_sidebar_win)
local sidebar_lines = vim.api.nvim_buf_get_lines(sidebar_buf, 0, -1, false)
for index = #sidebar_lines - 2, #sidebar_lines do
    assert(
        vim.fn.strdisplaywidth(sidebar_lines[index]) <= sidebar_width,
        "sidebar footer exceeds narrow width: " .. sidebar_lines[index]
    )
end
vim.cmd("tabclose")
assert(sidebar.is_open())

assert(sidebar.close())
assert(not sidebar.is_open())

require("sess.ui.command").setup()
assert(vim.list_contains(vim.fn.getcompletion("Sess ", "cmdline"), "sidebar"))
local notifications = {}
local original_notify = vim.notify
vim.notify = function(message, level)
    notifications[#notifications + 1] = { message = message, level = level }
end
local failed_command = require("sess.ui.command").execute({
    fargs = { "load", "missing-session" },
    bang = false,
    line1 = 1,
    line2 = 1,
})
vim.notify = original_notify
assert(not failed_command)
local failure_count = 0
for _, notification in ipairs(notifications) do
    if notification.message:find("missing%-session", 1, false) then failure_count = failure_count + 1 end
end
assert(failure_count == 1, "command failure should be reported exactly once")
vim.cmd("Sess sidebar")
assert(sidebar.is_open())
vim.cmd("Sess sidebar")
assert(not sidebar.is_open())

sidebar.configure({ enabled = false })
local disabled_ok, disabled_err = sidebar.open()
assert(not disabled_ok)
assert(disabled_err and disabled_err:find("disabled", 1, true))
local command_ok = require("sess.ui.command").execute({
    fargs = { "sidebar" },
    bang = false,
    line1 = 1,
    line2 = 1,
})
assert(not command_ok)
sidebar.configure({ enabled = true })

vim.cmd("vertical 10split")
local narrow_ok = sidebar.open()
assert(not narrow_ok)
assert(not sidebar.is_open())
vim.cmd("close")

-- Wiping the sidebar buffer must close its owned window without leaving an
-- orphan split. A failed cleanup keeps ownership and reports the diagnostic.
assert(sidebar.open())
local wiped_win = vim.api.nvim_get_current_win()
local wiped_buf = vim.api.nvim_win_get_buf(wiped_win)
local original_win_close = vim.api.nvim_win_close
local replacement_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(wiped_win, replacement_buf)
vim.api.nvim_win_close = function(win, force)
    if win == wiped_win then error("injected buffer-wipe close failure") end
    return original_win_close(win, force)
end
local notifications = {}
local original_notify = vim.notify
vim.notify = function(message, level)
    notifications[#notifications + 1] = { message = message, level = level }
end
local wiped, wipe_err = pcall(vim.api.nvim_buf_delete, wiped_buf, { force = true })
vim.notify = original_notify
vim.api.nvim_win_close = original_win_close
assert(wiped, wipe_err)
assert(sidebar.is_open())
assert(vim.api.nvim_win_is_valid(wiped_win))
local wipe_diagnostic = false
for _, notification in ipairs(notifications) do
    if notification.message:find("after buffer wipe", 1, true) then wipe_diagnostic = true end
end
assert(wipe_diagnostic, "buffer-wipe close failure should be reported")
assert(sidebar.refresh())
assert(sidebar.close())

assert(sidebar.open())
local orphan_check_win = vim.api.nvim_get_current_win()
local orphan_check_buf = vim.api.nvim_win_get_buf(orphan_check_win)
local orphan_replacement_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(orphan_check_win, orphan_replacement_buf)
local reentry_attempted = false
local reentry_opened = false
local reentry_autocmd = vim.api.nvim_create_autocmd("WinClosed", {
    callback = function(args)
        if tonumber(args.match) == orphan_check_win then
            reentry_attempted = true
            reentry_opened = sidebar.open() == true
        end
    end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = orphan_check_buf,
    callback = function()
        vim.api.nvim_exec_autocmds("WinClosed", { pattern = tostring(orphan_check_win) })
    end,
})
vim.api.nvim_buf_delete(orphan_check_buf, { force = true })
vim.api.nvim_del_autocmd(reentry_autocmd)
assert(reentry_attempted, "WinClosed re-entry callback should run")
assert(not reentry_opened, "sidebar cleanup must reject nested open")
assert(not vim.api.nvim_win_is_valid(orphan_check_win))
assert(not sidebar.is_open())
local transient_windows = {}
for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.b[buf].sess_transient_ui then transient_windows[#transient_windows + 1] = win end
    end
end
assert(#transient_windows == 0, "buffer wipe must not leave an orphan sidebar window")
