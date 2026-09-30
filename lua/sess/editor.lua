local M = {}

local parking

-- Deprecated test/integration seams retained without giving the adapter
-- persistence knowledge. Lifecycle code uses the path-based methods below.
local legacy_snapshot = function() end
local legacy_load = function() end

local function command(cmd, path)
    vim.cmd({ cmd = cmd, args = path and { path } or {}, magic = { file = false, bar = false } })
end

-- Capture live buffer identities, not their contents. Unnamed/terminal buffers
-- can only be resumed in this process; persisted Vimscript cannot preserve jobs.
function M.capture()
    local view = {
        tabs = {},
        buffers = {},
        listing = {},
        current = vim.api.nvim_get_current_tabpage(),
        cwd = vim.fn.getcwd(-1, -1),
        this_session = vim.v.this_session,
    }

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        view.listing[buf] = vim.bo[buf].buflisted
        if vim.bo[buf].buflisted then
            view.buffers[buf] = true
        end
    end

    for index, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local entry = {
            layout = vim.fn.winlayout(index),
            windows = {},
            floats = {},
            current = vim.api.nvim_tabpage_get_win(tab),
        }

        entry.cwd = vim.fn.haslocaldir(-1, index) == 2 and vim.fn.getcwd(-1, index) or nil

        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
            local config = vim.api.nvim_win_get_config(win)
            local buf = vim.api.nvim_win_get_buf(win)
            if not vim.b[buf].sess_mark_window then
                view.buffers[buf] = true

                local saved = vim.api.nvim_win_call(win, function()
                    return {
                        buf = buf,
                        view = vim.fn.winsaveview(),
                        width = vim.api.nvim_win_get_width(win),
                        height = vim.api.nvim_win_get_height(win),
                        cwd = vim.fn.haslocaldir() == 1 and vim.fn.getcwd() or nil,
                    }
                end)

                if config.relative == "" and not config.external then
                    entry.windows[win] = saved
                else
                    table.insert(entry.floats, { id = win, config = config, saved = saved })
                end
            elseif entry.current == win then
                for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
                    local candidate_buf = vim.api.nvim_win_get_buf(candidate)
                    if not vim.b[candidate_buf].sess_mark_window then
                        entry.current = candidate
                        break
                    end
                end
            end
        end

        entry.id = tab
        table.insert(view.tabs, entry)
    end

    return view
end

-- Prevent normal window/buffer switches from writing or destroying buffers,
-- including plugin buffers with bufhidden=wipe/delete/unload. Trusted sourced
-- code or user autocommands can still explicitly destroy state.
function M.protected(fn)
    local options =
        { hidden = vim.o.hidden, autowrite = vim.o.autowrite, autowriteall = vim.o.autowriteall }
    local hidden = {}

    local ok, result = xpcall(function()
        for _, buf in ipairs(vim.api.nvim_list_bufs()) do
            hidden[buf] = vim.bo[buf].bufhidden
            vim.bo[buf].bufhidden = "hide"
        end

        vim.o.hidden, vim.o.autowrite, vim.o.autowriteall = true, false, false

        return fn()
    end, debug.traceback)

    local cleanup_errors = {}

    for buf, value in pairs(hidden) do
        if vim.api.nvim_buf_is_valid(buf) then
            local restored, err =
                pcall(vim.api.nvim_set_option_value, "bufhidden", value, { buf = buf })
            if not restored then
                table.insert(cleanup_errors, tostring(err))
            end
        end
    end

    for name, value in pairs(options) do
        local restored, err = pcall(vim.api.nvim_set_option_value, name, value, {})
        if not restored then
            table.insert(cleanup_errors, tostring(err))
        end
    end

    if #cleanup_errors > 0 then
        return false,
            (ok and "" or tostring(result) .. "; ") .. "option cleanup failed: " .. table.concat(
                cleanup_errors,
                "; "
            )
    end

    return ok, result
end

function M.hide()
    -- Close views, not buffers. No bang: errors must not force-discard data.
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= "" or config.external then
            vim.api.nvim_win_close(win, false)
        end
    end

    vim.cmd("silent tabonly")
    vim.cmd("silent only")

    if not parking or not vim.api.nvim_buf_is_valid(parking) then
        parking = vim.api.nvim_create_buf(false, true)
    end

    vim.api.nvim_win_set_buf(0, parking)

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        vim.bo[buf].buflisted = false
    end
end

function M.empty(cwd)
    M.hide()
    command("cd", cwd)
    vim.api.nvim_win_set_buf(0, vim.api.nvim_create_buf(true, false))
    vim.v.this_session = ""
end

local function layout(node, windows, win, mapping)
    if node[1] == "leaf" then
        local saved = windows[node[2]]
        if not saved then
            return
        end

        mapping[node[2]] = win
        if vim.api.nvim_buf_is_valid(saved.buf) then
            vim.api.nvim_win_set_buf(win, saved.buf)
        end

        vim.api.nvim_win_call(win, function()
            if saved.cwd then
                command("lcd", saved.cwd)
            end

            vim.fn.winrestview(saved.view)
        end)

        return
    end

    local children, handles = node[2], { win }

    for i = 2, #children do
        vim.api.nvim_set_current_win(handles[i - 1])
        vim.cmd(node[1] == "row" and "rightbelow vsplit" or "rightbelow split")
        handles[i] = vim.api.nvim_get_current_win()
    end

    for i, child in ipairs(children) do
        layout(child, windows, handles[i], mapping)
    end
end

function M.restore(view, rollback)
    M.hide()
    command("cd", view.cwd)

    local selected
    local diagnostics = {}

    for index, tab in ipairs(view.tabs) do
        if index > 1 then
            vim.cmd("tabnew")
        end

        -- New tabs inherit the previous window's local cwd. Clear inherited
        -- scopes before applying this tab's own saved scopes.
        command("cd", view.cwd)
        if tab.cwd then
            command("tcd", tab.cwd)
        end

        local mapping = {}
        layout(tab.layout, tab.windows, vim.api.nvim_get_current_win(), mapping)

        for old, win in pairs(mapping) do
            local width_ok, width_err = pcall(
                vim.api.nvim_win_set_width,
                win,
                tab.windows[old].width
            )
            if not width_ok then
                table.insert(
                    diagnostics,
                    string.format("failed to restore window %s width: %s", old, tostring(width_err))
                )
            end

            local height_ok, height_err = pcall(
                vim.api.nvim_win_set_height,
                win,
                tab.windows[old].height
            )
            if not height_ok then
                table.insert(
                    diagnostics,
                    string.format("failed to restore window %s height: %s", old, tostring(height_err))
                )
            end
        end

        for _, float in ipairs(tab.floats) do
            if vim.api.nvim_buf_is_valid(float.saved.buf) then
                local config = vim.deepcopy(float.config)
                if config.relative == "win" then
                    config.win = mapping[config.win] or vim.api.nvim_get_current_win()
                end

                local win = vim.api.nvim_open_win(float.saved.buf, false, config)
                mapping[float.id] = win
                vim.api.nvim_win_call(win, function()
                    if float.saved.cwd then
                        command("lcd", float.saved.cwd)
                    end

                    vim.fn.winrestview(float.saved.view)
                end)
            end
        end

        if mapping[tab.current] then
            vim.api.nvim_set_current_win(mapping[tab.current])
        end

        if tab.id == view.current then
            selected = vim.api.nvim_get_current_win()
        end
    end

    for buf, listed in pairs(view.listing) do
        if vim.api.nvim_buf_is_valid(buf) and (rollback or view.buffers[buf]) then
            vim.bo[buf].buflisted = listed
        end
    end

    if selected then
        vim.api.nvim_set_current_win(selected)
    end

    vim.v.this_session = view.this_session

    return diagnostics
end

-- Source a persisted snapshot selected by the lifecycle/storage layers.
-- The editor adapter intentionally does not resolve or validate session IDs.
M.snapshot = legacy_snapshot
M.load = legacy_load
M._legacy_snapshot = legacy_snapshot
M._legacy_load = legacy_load

function M.source_snapshot(snapshot_path)
    command("source", snapshot_path)
end

-- Write a snapshot to the caller-provided temporary path. Storage owns the
-- replacement policy and supplies this path.
function M.write_snapshot(snapshot_path, legacy_item)
    if M.snapshot ~= legacy_snapshot then
        return M.snapshot(legacy_item)
    end

    vim.cmd({
        cmd = "mksession",
        bang = true,
        args = { snapshot_path },
        magic = { file = false, bar = false },
    })
end

-- Focus an existing visible buffer without creating windows or loading files.
function M.focus_buffer(bufnr, preferred_winid)
    local valid, is_valid = pcall(vim.api.nvim_buf_is_valid, bufnr)
    if not valid or not is_valid then
        return false, "buffer is unavailable"
    end

    local function contains(win)
        local ok, value = pcall(vim.api.nvim_win_get_buf, win)
        return ok and value == bufnr
    end

    local function focus(win)
        local ok, err = pcall(vim.api.nvim_set_current_win, win)
        if ok then
            return true, win
        end
        return false, tostring(err)
    end

    if preferred_winid then
        local ok, win_valid = pcall(vim.api.nvim_win_is_valid, preferred_winid)
        if ok and win_valid and contains(preferred_winid) then
            return focus(preferred_winid)
        end
    end

    for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
            if contains(win) then
                local switched, switch_err = pcall(vim.api.nvim_set_current_tabpage, tab)
                if not switched then
                    return false, tostring(switch_err)
                end
                return focus(win)
            end
        end
    end

    return false, "agent target is unavailable"
end

return M
