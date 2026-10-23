local editor = require("sess.editor")
local display = require("sess.ui.display")

local M = {}
local expression
local remembered = {}
local rendered_geometry
local renderer_confirmed = false
local sync_pending = false
local reconcile_provider

local function editing_window(win, tab)
    return type(win) == "number"
        and win > 0
        and vim.api.nvim_win_is_valid(win)
        and vim.api.nvim_win_get_tabpage(win) == tab
        and vim.api.nvim_win_get_config(win).relative == ""
        and not editor.is_transient_window(win)
end

local function remember()
    local tab = vim.api.nvim_get_current_tabpage()
    local win = vim.api.nvim_get_current_win()
    if editing_window(win, tab) then
        remembered[tab] = { win = win, buf = vim.api.nvim_win_get_buf(win) }
    end
end

local function sync_sidebar()
    if sync_pending then
        return
    end
    sync_pending = true
    vim.schedule(function()
        sync_pending = false
        if reconcile_provider then
            reconcile_provider()
        end
        local sidebar = package.loaded["sess.ui.sidebar"]
        if sidebar then
            sidebar.redraw_heading()
        end
    end)
end

local function geometry()
    if not expression or vim.o.tabline ~= expression or vim.o.showtabline == 0 then
        return nil
    end
    if vim.o.showtabline == 1 and #vim.api.nvim_list_tabpages() < 2 then
        return nil
    end
    for _, ui in ipairs(vim.api.nvim_list_uis()) do
        if ui.ext_tabline then
            return nil
        end
    end
    local sidebar = package.loaded["sess.ui.sidebar"]
    return sidebar and sidebar.tabline_geometry() or nil
end

--- Opt in for an exact native 'tabline' expression, or pass false to disable.
--- Does not set 'tabline' or 'showtabline'.
function M.setup(value)
    if value ~= false and (type(value) ~= "string" or value == "") then
        return false, "tabline expression must be a non-empty string or false"
    end
    expression = value or nil
    rendered_geometry = nil
    renderer_confirmed = false
    remember()
    sync_sidebar()
    vim.cmd.redrawtabline()
    return true
end

--- Return an escaped filename label for a tabpage handle (current by default).
function M.label(tab)
    tab = tab or vim.api.nvim_get_current_tabpage()
    if type(tab) ~= "number" or not vim.api.nvim_tabpage_is_valid(tab) then
        return "[No Name]"
    end
    local win = vim.api.nvim_tabpage_get_win(tab)
    if not editing_window(win, tab) then
        local previous = remembered[tab]
        win = previous and previous.win or nil
        if not editing_window(win, tab) or vim.api.nvim_win_get_buf(win) ~= previous.buf then
            win = nil
            for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
                if editing_window(candidate, tab) then
                    win = candidate
                    break
                end
            end
        end
    end
    if not win then
        return "[No Name]"
    end
    local buf = vim.api.nvim_win_get_buf(win)
    remembered[tab] = { win = win, buf = buf }
    local name = vim.api.nvim_buf_get_name(buf)
    name = name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":t")
    -- Labels are text, never statusline expressions. Normalize control bytes
    -- before display-cell measurement by Neovim's tabline renderer.
    return (name:gsub("[%c]", " "):gsub("%%", "%%%%"))
end

--- Wrap trusted native tabline format text; preserve it verbatim on fallback.
function M.render(content)
    local offset = geometry()
    if offset then
        renderer_confirmed = true
    end
    if not vim.deep_equal(rendered_geometry, offset) then
        rendered_geometry = offset
        sync_sidebar()
    end
    if not offset then
        return content
    end
    local title = display.truncate_end("ACTIVE SESSIONS", offset.width)
    title = "%T%#SessSidebarTitle#"
        .. title
        .. string.rep(" ", offset.width - vim.fn.strdisplaywidth(title))
    -- A bounded group keeps content (and its native click/highlight codes)
    -- out of the heading, even with long or wide-character filenames.
    local function bounded(width)
        return "%-" .. width .. "." .. width .. "(" .. content .. "%T%#TabLineFill#%)"
    end
    if offset.col == 0 then
        return title .. "%#TabLineFill# " .. bounded(vim.o.columns - offset.width - 1)
    end
    return bounded(offset.col) .. title
end

--- Render the built-in native tab list with tab-number click targets.
function M.provider()
    local tabs = {}
    local current = vim.api.nvim_get_current_tabpage()
    for number, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local highlight = tab == current and "TabLineSel" or "TabLine"
        tabs[#tabs + 1] = "%"
            .. number
            .. "T%#"
            .. highlight
            .. "# "
            .. number
            .. ": "
            .. M.label(tab)
            .. " "
    end
    return M.render(table.concat(tabs) .. "%T%#TabLineFill#")
end

-- Partial :set operations preserve Neovim's hidden insecure-option flag.
-- Full API assignments would promote sandboxed expressions to trusted code.
local function replace_preserving_trust(value)
    for _, change in ipairs({ { "-=", vim.o.tabline }, { "+=", value } }) do
        vim.api.nvim_cmd({
            cmd = "set",
            args = { "tabline" .. change[1] .. vim.fn.escape(change[2], ' \\"\t\n') },
            magic = { bar = false, file = false },
            mods = { noautocmd = true },
        }, {})
    end
end

--- Clear confirmation before evaluating a captured provider, including failures.
function M.begin_render()
    if renderer_confirmed then
        renderer_confirmed = false
        sync_sidebar()
    end
    return 0
end

-- Only inspect executable tokens; text and quoted literals are not references.
local function has_script_local_reference(value)
    local is_format = value:sub(1, 2) ~= "%!"
    local in_expression = not is_format
    local i = is_format and 1 or 3
    local quote
    while i <= #value do
        local char = value:sub(i, i)
        local pair = value:sub(i, i + 1)
        if quote then
            if (quote == '"' and char == "\\") or (quote == "'" and pair == "''") then
                i = i + 1
            elseif char == quote then
                quote = nil
            end
        elseif not in_expression then
            if pair == "%%" then
                i = i + 1
            elseif pair == "%{" then
                in_expression = true
                i = i + 1
            end
        elseif char == "'" or char == '"' then
            quote = char
        elseif
            (pair == "s:" and not value:sub(i - 1, i - 1):match("[%w_]"))
            or value:sub(i, i + 4) == "<SID>"
        then
            return true
        elseif is_format and char == "}" then
            in_expression = false
        end
        i = i + 1
    end
    return false
end

--- Decorate an existing native tabline, or supply the built-in clickable UI.
--- Never changes tabline visibility.
function M.install()
    local original = vim.o.tabline
    local built_in = "%!v:lua.require'sess.ui.tabline'.provider()"
    if original == "" or original == built_in then
        vim.o.tabline = built_in
        return M.setup(built_in)
    end
    if has_script_local_reference(original) then
        expression = nil
        rendered_geometry = nil
        renderer_confirmed = false
        reconcile_provider = nil
        sync_sidebar()
        require("sess.log").warn(
            "tabline: raw script-local tabline left unchanged; use explicit <SNR> references"
        )
        return true
    end
    -- Keep expression evaluation in Neovim, in the original caller context.
    -- The bridge catches sandbox prohibition without executing any Lua there.
    local bridge = vim.api.nvim_exec2(
        [[
        let s:blocked = v:false
        function! s:begin() abort
            try
                call v:lua.require'sess.ui.tabline'.begin_render()
            catch /^Vim\%((\a\+)\)\=:E48:/
                let s:blocked = v:true
            endtry
            return 0
        endfunction
        function! s:wrap(content) abort
            try
                return v:lua.require'sess.ui.tabline'.render(a:content)
            catch /^Vim\%((\a\+)\)\=:E48:/
                let s:blocked = v:true
                return a:content
            endtry
        endfunction
        function! s:blocked() abort
            return s:blocked
        endfunction
        echo expand('<SID>')
    ]],
        { output = true }
    ).output
    local content = original:sub(1, 2) == "%!" and "(" .. original:sub(3) .. ")"
        or vim.fn.string(original)
    local value = "%!" .. bridge .. "wrap([" .. bridge .. "begin(), " .. content .. "][1])"
    replace_preserving_trust(value)
    reconcile_provider = function()
        if not vim.fn.call(bridge .. "blocked", {}) then
            return
        end
        reconcile_provider = nil
        if vim.o.tabline == value then
            replace_preserving_trust(original)
            M.setup(false)
            require("sess.log").warn("tabline: sandboxed tabline left unchanged")
        end
    end
    local ok, err = pcall(M.setup, value)
    if not ok then
        vim.schedule(function()
            require("sess.log").warn("tabline: " .. tostring(err))
        end)
    end
    return true
end

-- Once confirmed, ownership follows availability, not the previous frame's
-- window/width. Reattaching or resizing must not briefly restore the buffer title.
-- Buffer updates remain deferred out of tabline evaluation/textlock.
function M.heading_visible()
    return renderer_confirmed and geometry() ~= nil
end

local group = vim.api.nvim_create_augroup("sess-tabline", { clear = true })
vim.api.nvim_create_autocmd({ "WinLeave", "BufEnter" }, {
    group = group,
    callback = remember,
})
vim.api.nvim_create_autocmd(
    { "TabEnter", "TabClosed", "WinClosed", "WinResized", "VimResized", "UIEnter", "UILeave" },
    {
        group = group,
        callback = function()
            for tab in pairs(remembered) do
                if not vim.api.nvim_tabpage_is_valid(tab) then
                    remembered[tab] = nil
                end
            end
            sync_sidebar()
        end,
    }
)
vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "tabline", "showtabline" },
    callback = sync_sidebar,
})
-- A first render may be sandboxed long after setup's scheduled work finishes.
-- Check directly at idle: sandboxed Vimscript cannot schedule Lua, and scheduling
-- unconditionally from SafeState would keep the editor from settling at idle.
vim.api.nvim_create_autocmd("SafeState", {
    group = group,
    callback = function()
        if reconcile_provider then
            reconcile_provider()
        end
    end,
})

return M
