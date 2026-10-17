local M = {}

local parking

-- Transient UI owners temporarily remove their windows while the editor
-- changes layouts or writes Vim session files. The adapter knows only this
-- generic boundary; each owner keeps its own logical state.
local transient_owners = {}
local transient_suspend_depth = 0

function M.register_transient_owner(owner)
    if type(owner) ~= "table" then
        return false, "transient owner must be a table"
    end
    if type(owner.suspend) ~= "function" or type(owner.resume) ~= "function" then
        return false, "transient owner must provide suspend and resume callbacks"
    end
    transient_owners[#transient_owners + 1] = owner
    return true
end

function M.is_transient_ui_suspended()
    return transient_suspend_depth > 0
end

local function transient_call(fn)
    local outer = transient_suspend_depth == 0
    local suspended = {}

    -- Establish the guard before callbacks run. A callback may invoke another
    -- editor operation, which must share this suspension rather than suspend
    -- every owner recursively.
    transient_suspend_depth = transient_suspend_depth + 1
    if outer then
        for _, owner in ipairs(transient_owners) do
            local called, ok, err = pcall(owner.suspend)
            if not called or ok == false then
                -- Keep the guard active while already-suspended owners roll
                -- back; their callbacks may also perform editor operations.
                for index = #suspended, 1, -1 do
                    pcall(suspended[index].resume)
                end
                transient_suspend_depth = transient_suspend_depth - 1
                return false, (called and err) or ok or "transient UI suspend failed"
            end
            suspended[#suspended + 1] = owner
        end
    end

    local results = { xpcall(fn, debug.traceback) }
    local called = table.remove(results, 1)

    local resume_error
    if outer then
        -- Keep the guard active through resume callbacks as well.
        for index = #suspended, 1, -1 do
            local resumed, ok, err = pcall(suspended[index].resume)
            if not resumed or ok == false then
                resume_error = resume_error
                    or (resumed and err)
                    or ok
                    or "transient UI resume failed"
            end
        end
    end
    transient_suspend_depth = transient_suspend_depth - 1

    if not called then
        return false, results[1]
    end
    if resume_error then
        return false, "transient UI resume failed: " .. tostring(resume_error)
    end
    return unpack(results)
end

-- Deprecated test/integration seams retained without giving the adapter
-- persistence knowledge. Lifecycle code uses the path-based methods below.
local legacy_snapshot = function() end
local legacy_load = function() end

local function command(cmd, path)
    vim.cmd({ cmd = cmd, args = path and { path } or {}, magic = { file = false, bar = false } })
end

-- Neovim's ui2 windows are owned by the editor, not by a session. Keep them
-- out of captured views and do not close them while changing sessions.
local ui2
local function get_ui2()
    if ui2 == nil then
        local ok, module = pcall(require, "vim._core.ui2")
        ui2 = ok and module or false
    end

    return ui2 or nil
end

local function is_ui2_window(win)
    local module = get_ui2()
    if not module then
        return false
    end

    for _, target in pairs(module.wins or {}) do
        if target == win then
            return true
        end
    end

    return false
end

local function is_ui2_buffer(buf)
    local module = get_ui2()
    if not module then
        return false
    end

    for _, target in pairs(module.bufs or {}) do
        if target == buf then
            return true
        end
    end

    return false
end

-- Transient UI is an editor-owned surface, not session content. Owners mark
-- their buffers (or windows) with this generic marker; the editor adapter does
-- not need to know which UI owns them.
function M.is_transient_buffer(buf)
    local valid, is_valid = pcall(vim.api.nvim_buf_is_valid, buf)
    return valid and is_valid and vim.b[buf].sess_transient_ui == true
end

function M.is_transient_window(win)
    local valid, is_valid = pcall(vim.api.nvim_win_is_valid, win)
    if not valid or not is_valid then
        return false
    end

    if vim.w[win].sess_transient_ui == true then
        return true
    end

    local buffer_ok, buf = pcall(vim.api.nvim_win_get_buf, win)
    return buffer_ok and M.is_transient_buffer(buf) or false
end

local function is_transient_only_buffer(buf)
    local called, windows = pcall(vim.fn.win_findbuf, buf)
    if not called or type(windows) ~= "table" or #windows == 0 then
        return false
    end

    for _, win in ipairs(windows) do
        if not M.is_transient_window(win) then
            return false
        end
    end
    return true
end

local function is_session_excluded_buffer(buf)
    return is_ui2_buffer(buf)
        or vim.b[buf].sess_mark_window
        or M.is_transient_buffer(buf)
        or is_transient_only_buffer(buf)
end

local function is_session_excluded_window(win, buf)
    return is_ui2_window(win)
        or vim.w[win].sess_mark_window
        or (buf and vim.b[buf].sess_mark_window)
        or M.is_transient_window(win)
end

local function prune_layout(node)
    if type(node) ~= "table" then
        return nil
    end

    if node[1] == "leaf" then
        if M.is_transient_window(node[2]) then
            return nil
        end
        return { "leaf", node[2] }
    end

    local children = {}
    for _, child in ipairs(node[2] or {}) do
        local kept = prune_layout(child)
        if kept then
            children[#children + 1] = kept
        end
    end

    if #children == 0 then
        return nil
    elseif #children == 1 then
        return children[1]
    end

    return { node[1], children }
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
        if not is_session_excluded_buffer(buf) then
            view.listing[buf] = vim.bo[buf].buflisted
            if vim.bo[buf].buflisted then
                view.buffers[buf] = true
            end
        end
    end

    for index, tab in ipairs(vim.api.nvim_list_tabpages()) do
        local entry = {
            layout = prune_layout(vim.fn.winlayout(index)),
            windows = {},
            floats = {},
            current = vim.api.nvim_tabpage_get_win(tab),
        }

        entry.cwd = vim.fn.haslocaldir(-1, index) == 2 and vim.fn.getcwd(-1, index) or nil

        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
            local config = vim.api.nvim_win_get_config(win)
            local buf = vim.api.nvim_win_get_buf(win)
            if not is_session_excluded_window(win, buf) then
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
                    if not is_session_excluded_window(candidate, candidate_buf) then
                        entry.current = candidate
                        break
                    end
                end
            end
        end

        entry.id = tab
        if entry.layout then
            table.insert(view.tabs, entry)
        end
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
            if not is_session_excluded_buffer(buf) then
                hidden[buf] = vim.bo[buf].bufhidden
                vim.bo[buf].bufhidden = "hide"
            end
        end

        vim.o.hidden, vim.o.autowrite, vim.o.autowriteall = true, false, false

        return { transient_call(fn) }
    end, debug.traceback)

    local action_ok = ok and result[1] ~= false
    local action_err = ok and result[2] or result
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
        local action_message = action_ok and "" or tostring(action_err) .. "; "
        return false,
            action_message .. "option cleanup failed: " .. table.concat(cleanup_errors, "; ")
    end

    if not action_ok then
        return false, tostring(action_err or "editor action failed")
    end

    return true, result[1]
end

local function close_window(win)
    local valid, is_valid = pcall(vim.api.nvim_win_is_valid, win)
    if not valid or not is_valid then
        return true
    end

    local closed, err = pcall(vim.api.nvim_win_close, win, false)
    if not closed then
        return false, tostring(err)
    end

    return true
end

function M.hide()
    -- Close views, not buffers. No bang: errors must not force-discard data.
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local valid, config = pcall(vim.api.nvim_win_get_config, win)
        if valid
            and (config.relative ~= "" or config.external)
            and not is_session_excluded_window(win, vim.api.nvim_win_get_buf(win))
        then
            local closed, err = close_window(win)
            if not closed then
                error(err)
            end
        end
    end

    local tabs_closed, tabs_err = pcall(vim.cmd, "silent tabonly")
    if not tabs_closed then
        error(tostring(tabs_err))
    end

    -- Tab teardown can queue plugin callbacks that still refer to the buffers
    -- being hidden. Let those callbacks observe the live buffers before the
    -- caller performs any destructive unload step.
    local drained, drain_err = pcall(vim.wait, 0)
    if not drained then
        error(tostring(drain_err))
    end

    local current_tab = vim.api.nvim_get_current_tabpage()
    local keep
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
        local config = vim.api.nvim_win_get_config(win)
        if
            config.relative == ""
            and not config.external
            and not is_session_excluded_window(win, vim.api.nvim_win_get_buf(win))
        then
            keep = win
            break
        end
    end

    if keep then
        vim.api.nvim_set_current_win(keep)
        for _, win in ipairs(vim.api.nvim_tabpage_list_wins(current_tab)) do
            if
                win ~= keep
                and not is_session_excluded_window(win, vim.api.nvim_win_get_buf(win))
            then
                local closed, err = close_window(win)
                if not closed then
                    error(err)
                end
            end
        end
    end

    if not parking or not vim.api.nvim_buf_is_valid(parking) then
        parking = vim.api.nvim_create_buf(false, true)
    end

    local parked, park_err = pcall(vim.api.nvim_win_set_buf, 0, parking)
    if not parked then
        error(tostring(park_err))
    end

    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if not is_session_excluded_buffer(buf) then
            vim.bo[buf].buflisted = false
        end
    end
end

local function is_clean_empty_buffer(buf)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return false
    end

    if vim.bo[buf].modified or vim.api.nvim_buf_get_name(buf) ~= "" then
        return false
    end

    return vim.api.nvim_buf_line_count(buf) == 1
        and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

local function remove_restore_placeholder(buf, diagnostics)
    if M.is_transient_buffer(buf) or not is_clean_empty_buffer(buf) or #vim.fn.win_findbuf(buf) > 0 then
        return
    end

    local removed, remove_err = pcall(vim.api.nvim_buf_delete, buf, {})
    if not removed then
        table.insert(
            diagnostics,
            "failed to remove temporary restore buffer: " .. tostring(remove_err)
        )
    end
end

local function empty_impl(cwd, options)
    M.hide()
    command("cd", cwd)

    local empty
    if options and options.reuse_clean and is_clean_empty_buffer(parking) then
        empty = parking
        if vim.bo[empty].buftype == "nofile" then
            vim.bo[empty].buftype = ""
        end
        vim.bo[empty].bufhidden = "hide"
        vim.bo[empty].buflisted = true
    else
        empty = vim.api.nvim_create_buf(true, false)
    end

    local changed, change_err = pcall(vim.api.nvim_win_set_buf, 0, empty)
    if not changed then
        pcall(vim.api.nvim_buf_delete, empty, { force = true })
        error(tostring(change_err))
    end
    vim.v.this_session = ""
end

function M.empty(cwd, options)
    local emptied, err = transient_call(function()
        return empty_impl(cwd, options)
    end)
    if emptied == false and err then error(err) end
    return emptied
end

local function layout(node, windows, win, mapping)
    local valid, is_valid = pcall(vim.api.nvim_win_is_valid, win)
    if not valid or not is_valid then
        return false, "window disappeared while restoring session layout"
    end

    if node[1] == "leaf" then
        local saved = windows[node[2]]
        if not saved then
            return true
        end

        mapping[node[2]] = win
        local buffer_valid, is_buffer_valid = pcall(vim.api.nvim_buf_is_valid, saved.buf)
        if buffer_valid and is_buffer_valid then
            local changed, change_err = pcall(vim.api.nvim_win_set_buf, win, saved.buf)
            if not changed then
                return false, tostring(change_err)
            end
        end

        local called, call_err = pcall(vim.api.nvim_win_call, win, function()
            if saved.cwd then
                command("lcd", saved.cwd)
            end

            vim.fn.winrestview(saved.view)
        end)
        if not called then
            return false, tostring(call_err)
        end

        return true
    end

    local children, handles = node[2], { win }

    for i = 2, #children do
        local focused, focus_err = pcall(vim.api.nvim_set_current_win, handles[i - 1])
        if not focused then
            return false, tostring(focus_err)
        end

        local split, split_err = pcall(
            vim.cmd,
            node[1] == "row" and "rightbelow vsplit" or "rightbelow split"
        )
        if not split then
            return false, tostring(split_err)
        end
        handles[i] = vim.api.nvim_get_current_win()
    end

    for i, child in ipairs(children) do
        local restored, restore_err = layout(child, windows, handles[i], mapping)
        if not restored then
            return false, restore_err
        end
    end

    return true
end

local function restore_impl(view, rollback)
    M.hide()
    command("cd", view.cwd)

    local selected
    local diagnostics = {}
    local tabs = {}
    for _, tab in ipairs(view.tabs) do
        if tab.layout then
            tabs[#tabs + 1] = tab
        end
    end

    for index, tab in ipairs(tabs) do
        local restore_placeholder
        if index > 1 then
            vim.cmd("tabnew")
            restore_placeholder = vim.api.nvim_get_current_buf()
        end

        -- New tabs inherit the previous window's local cwd. Clear inherited
        -- scopes before applying this tab's own saved scopes.
        command("cd", view.cwd)
        if tab.cwd then
            command("tcd", tab.cwd)
        end

        local mapping = {}
        local laid_out, layout_err = layout(
            tab.layout,
            tab.windows,
            vim.api.nvim_get_current_win(),
            mapping
        )
        if not laid_out then
            error(layout_err)
        end

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
                    string.format(
                        "failed to restore window %s height: %s",
                        old,
                        tostring(height_err)
                    )
                )
            end
        end

        for _, float in ipairs(tab.floats) do
            local buffer_valid, is_buffer_valid = pcall(vim.api.nvim_buf_is_valid, float.saved.buf)
            if buffer_valid and is_buffer_valid then
                local config = vim.deepcopy(float.config)
                if config.relative == "win" then
                    config.win = mapping[config.win] or vim.api.nvim_get_current_win()
                end

                local opened, win = pcall(vim.api.nvim_open_win, float.saved.buf, false, config)
                if not opened then
                    error(tostring(win))
                end
                mapping[float.id] = win
                local called, call_err = pcall(vim.api.nvim_win_call, win, function()
                    if float.saved.cwd then
                        command("lcd", float.saved.cwd)
                    end

                    vim.fn.winrestview(float.saved.view)
                end)
                if not called then
                    error(tostring(call_err))
                end
            end
        end

        remove_restore_placeholder(restore_placeholder, diagnostics)

        if mapping[tab.current] then
            local focused, focus_err = pcall(vim.api.nvim_set_current_win, mapping[tab.current])
            if not focused then
                error(tostring(focus_err))
            end
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
        local focused, focus_err = pcall(vim.api.nvim_set_current_win, selected)
        if not focused then
            error(tostring(focus_err))
        end
    end

    vim.v.this_session = view.this_session

    return diagnostics
end

function M.restore(view, rollback)
    local restored, err = transient_call(function()
        return restore_impl(view, rollback)
    end)
    if restored == false and err then error(err) end
    return restored
end

-- Source a persisted snapshot selected by the lifecycle/storage layers.
-- The editor adapter intentionally does not resolve or validate session IDs.
M.snapshot = legacy_snapshot
M.load = legacy_load
M._legacy_snapshot = legacy_snapshot
M._legacy_load = legacy_load

local function leave_terminal_mode()
    if vim.api.nvim_get_mode().mode ~= "t" then
        return true
    end

    local normal_mode_keys = vim.api.nvim_replace_termcodes("<C-\\><C-N>", true, false, true)
    local feed_ok, feed_error = pcall(vim.api.nvim_feedkeys, normal_mode_keys, "nx", false)
    if not feed_ok then
        return false, "failed to leave terminal mode: " .. tostring(feed_error)
    end

    if vim.api.nvim_get_mode().mode == "t" then
        return false, "failed to leave terminal mode"
    end

    return true
end

function M.source_snapshot(snapshot_path, content)
    if type(content) ~= "string" then
        return false, "secure session snapshot content is required"
    end

    local terminal_mode_left, terminal_error = leave_terminal_mode()
    if not terminal_mode_left then
        return false, terminal_error
    end

    -- Storage reads the snapshot through its descriptor-relative, no-follow
    -- boundary. Execute those bytes directly; :source would reopen a pathname
    -- after that validation and reintroduce the leaf-replacement race.
    vim.api.nvim_exec(content, false)
    vim.v.this_session = snapshot_path
    return true
end

local function open_descriptor_path(fd)
    for _, prefix in ipairs({ "/proc/self/fd", "/dev/fd" }) do
        local candidate = prefix .. "/" .. tostring(fd)
        local stat = vim.uv.fs_stat(candidate)
        if stat and stat.type == "file" then
            return candidate
        end
    end
    return nil
end

-- Write a snapshot to the caller-provided temporary path. Storage owns the
-- replacement policy and supplies this path. When a descriptor is supplied,
-- pass the descriptor itself to :mksession so Vim cannot redirect the write
-- by replacing the temporary pathname.
function M.write_snapshot(snapshot_path, legacy_item, fd)
    if M.snapshot ~= legacy_snapshot then
        return transient_call(function()
            return M.snapshot(legacy_item)
        end)
    end

    local destination = snapshot_path
    if fd then
        destination = open_descriptor_path(fd)
        if not destination then
            return false, "secure snapshot descriptor path is unavailable"
        end
    end

    return transient_call(function()
        local ok, err = pcall(vim.cmd, {
            cmd = "mksession",
            bang = true,
            args = { destination },
            magic = { file = false, bar = false },
        })
        if not ok then
            return false, tostring(err)
        end
        return true
    end)
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
