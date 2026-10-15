local M = {}

local selection = require("telescope._extensions.sess.selection")

local DEFAULT_POLL_INTERVAL = 1000

local function copy_table(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for key, child in pairs(value) do
        copy[key] = child
    end
    return copy
end

local function capture_manager_fields(manager)
    if type(manager) ~= "table" then
        return nil
    end
    local ok, fields = pcall(function()
        local captured = {}
        for key, value in pairs(manager) do
            if type(value) == "table" then
                local array = true
                for child_key in pairs(value) do
                    if type(child_key) ~= "number" then
                        array = false
                        break
                    end
                end
                if array then
                    captured[key] = copy_table(value)
                else
                    local copied, copy = pcall(vim.deepcopy, value)
                    captured[key] = copied and copy or value
                end
            else
                captured[key] = value
            end
        end
        return captured
    end)
    return ok and fields or nil
end

local function restore_manager_fields(manager, fields)
    if type(manager) ~= "table" or type(fields) ~= "table" then
        return
    end
    pcall(function()
        for key in pairs(manager) do
            manager[key] = nil
        end
        for key, value in pairs(fields) do
            manager[key] = value
        end
    end)
end

local function capture_prompt(picker)
    if not picker then
        return nil
    end
    if type(picker.get_prompt) == "function" then
        local ok, prompt = pcall(picker.get_prompt, picker)
        if ok and type(prompt) == "string" then
            return prompt
        end
    end
    if type(picker.prompt) == "string" then
        return picker.prompt
    end
    if type(picker.prompt_bufnr) == "number" then
        local ok, prompt = pcall(function()
            if not vim.api.nvim_buf_is_valid(picker.prompt_bufnr) then
                return nil
            end
            return vim.api.nvim_buf_get_lines(picker.prompt_bufnr, 0, 1, false)[1]
        end)
        if ok and type(prompt) == "string" then
            return prompt
        end
    end
    return nil
end

local function capture_state(picker)
    local state = {
        finder = picker.finder,
        manager = picker.manager,
        manager_fields = capture_manager_fields(picker.manager),
        snapshot = picker._sess_active_snapshot,
        expanded = picker._sess_expanded,
        expanded_fields = copy_table(picker._sess_expanded),
        prompt_title = picker.prompt_title,
        prompt = capture_prompt(picker),
        selection_entry = picker._selection_entry,
        selection_row = picker._selection_row,
    }
    local prompt_border = picker.layout
        and picker.layout.prompt
        and picker.layout.prompt.border
    if prompt_border then
        -- A nil title is meaningful: rollback must clear a candidate title
        -- introduced by a partially failed refresh.
        state.border_title_present = true
        state.border_title = prompt_border.title
    end
    if type(picker.get_selection) == "function" then
        local ok, selected = pcall(picker.get_selection, picker)
        if ok then
            state.selected = selected
        end
    end
    if type(picker.results_bufnr) == "number" then
        local ok, valid = pcall(vim.api.nvim_buf_is_valid, picker.results_bufnr)
        if ok and valid then
            local rows_ok, rows = pcall(vim.api.nvim_buf_get_lines, picker.results_bufnr, 0, -1, false)
            if rows_ok then
                state.rows = rows
            end
        end
    end
    if type(picker.results_win) == "number" then
        local ok, valid = pcall(vim.api.nvim_win_is_valid, picker.results_win)
        if ok and valid then
            local cursor_ok, cursor = pcall(vim.api.nvim_win_get_cursor, picker.results_win)
            if cursor_ok then
                state.cursor = cursor
            end
        end
    end
    return state
end

local function restore_state(picker, state)
    picker.finder = state.finder
    picker.manager = state.manager
    restore_manager_fields(state.manager, state.manager_fields)
    picker._sess_active_snapshot = state.snapshot
    picker._sess_expanded = state.expanded
    if type(state.expanded) == "table" and type(state.expanded_fields) == "table" then
        for key in pairs(state.expanded) do
            state.expanded[key] = nil
        end
        for key, value in pairs(state.expanded_fields) do
            state.expanded[key] = value
        end
    end
    picker.prompt_title = state.prompt_title
    local prompt_border = picker.layout
        and picker.layout.prompt
        and picker.layout.prompt.border
    if prompt_border and state.border_title_present then
        pcall(prompt_border.change_title, prompt_border, state.border_title)
    end
    if state.prompt ~= nil then
        local restored = false
        if type(picker.set_prompt) == "function" then
            restored = pcall(picker.set_prompt, picker, state.prompt)
        elseif picker.prompt ~= nil then
            restored = pcall(function()
                picker.prompt = state.prompt
            end)
        end
        if not restored and type(picker.prompt_bufnr) == "number" then
            pcall(function()
                if vim.api.nvim_buf_is_valid(picker.prompt_bufnr) then
                    vim.api.nvim_buf_set_lines(picker.prompt_bufnr, 0, 1, false, { state.prompt })
                end
            end)
        end
    end
    if state.rows ~= nil and type(picker.results_bufnr) == "number" then
        pcall(function()
            if vim.api.nvim_buf_is_valid(picker.results_bufnr) then
                vim.api.nvim_buf_set_lines(picker.results_bufnr, 0, -1, false, state.rows)
            end
        end)
    end
    if state.cursor ~= nil and type(picker.results_win) == "number" then
        pcall(function()
            if vim.api.nvim_win_is_valid(picker.results_win) then
                vim.api.nvim_win_set_cursor(picker.results_win, state.cursor)
            end
        end)
    end
    picker._selection_entry = state.selection_entry
    picker._selection_row = state.selection_row
    local key = selection.key(state.selected and (state.selected.value or state.selected))
    if key then
        pcall(selection.restore, picker, state.finder, key, { parent = true })
    end
    if state.selection_entry ~= nil then
        picker._selection_entry = state.selection_entry
    end
end

-- Poll only while this picker is open, and redraw only when its rows change.
-- The generator receives a completion callback and may yield between probes.
function M.start(picker, generate, initial_rows, poll_interval)
    local prompt = picker.prompt_bufnr
    poll_interval = poll_interval or DEFAULT_POLL_INTERVAL
    if
        type(poll_interval) ~= "number"
        or poll_interval <= 0
        or poll_interval % 1 ~= 0
    then
        error("sess.nvim: poll_interval must be a positive integer in milliseconds")
    end
    if not prompt or not vim.api.nvim_buf_is_valid(prompt) then
        return
    end

    local timer
    local task
    local cancel_refresh
    local rows = initial_rows
    local stopped = false
    local refreshing = false
    local scheduled = false
    local pending_resize = false
    local snapshot_at_refresh
    local rollback_state
    local autocmds = {}
    picker._sess_active_refresh_transactional = true

    local function stop()
        if stopped then
            return
        end
        stopped = true
        refreshing = false
        pending_resize = false
        rollback_state = nil
        picker._sess_active_refresh_transactional = nil
        picker._sess_active_commit_title = nil
        if timer then
            timer:stop()
            timer:close()
        end
        if task then
            task:close()
        end
        if cancel_refresh then
            cancel_refresh()
            cancel_refresh = nil
        end
        for _, autocmd in ipairs(autocmds) do
            pcall(vim.api.nvim_del_autocmd, autocmd)
        end
        autocmds = {}
    end

    local function fail(err)
        -- A best-effort status probe must not close an otherwise usable picker.
        -- Keep the last committed rows and let the next poll retry it. Store a
        -- textual warning as well as logging it so status/footer integrations
        -- can expose the failure without relying on a highlight or icon.
        if stopped then
            return
        end
        refreshing = false
        local cancel = cancel_refresh
        cancel_refresh = nil
        if cancel then
            pcall(cancel)
        end
        picker._sess_active_loading = false
        picker._sess_active_refresh_warning = tostring(err)
        require("sess.log").warn("Active picker refresh failed: " .. tostring(err))
    end

    local refresh

    local function finish(generation, finder, next_rows, snapshot, unchanged)
        if stopped or not refreshing then
            return
        end

        -- A manual refresh and polling share this generation. Whichever
        -- request starts last owns the eventual commit; an older callback must
        -- not overwrite its rows, title, snapshot, or expansion state.
        if generation ~= picker._sess_active_refresh_generation then
            return
        end

        refreshing = false
        cancel_refresh = nil

        -- Ignore probes started before a user mutation replaced the cached
        -- snapshot while the probe was yielding. The newer mutation owns the
        -- picker state and must not be rolled back by this stale probe.
        if
            snapshot
            and snapshot_at_refresh
            and picker._sess_active_snapshot ~= snapshot_at_refresh
        then
            rollback_state = nil
            picker._sess_active_refresh_warning = nil
            if pending_resize and not stopped then
                pending_resize = false
                refresh()
            end
            return
        end

        if unchanged then
            -- The probe completed successfully but produced the same visible
            -- state. Commit the fresh snapshot for preview consumers without
            -- rebuilding Telescope's manager or invalidating its preview.
            if snapshot then
                picker._sess_active_snapshot = snapshot
            end
            rollback_state = nil
            picker._sess_active_refresh_warning = nil
            if pending_resize and not stopped then
                pending_resize = false
                refresh()
            end
            return
        end

        local ok, err = pcall(function()
            -- Collapsed rows can stay unchanged while a session status changes.
            -- Keep every field below speculative until Telescope accepts the
            -- candidate finder. In particular, snapshot assignment must follow
            -- picker:refresh so a partial refresh can be rolled back.
            local snapshot_changed = snapshot ~= nil
                and not vim.deep_equal(picker._sess_active_snapshot, snapshot)
            if snapshot_changed or not vim.deep_equal(rows, next_rows) then
                local selected_key = selection.key(
                    rollback_state and rollback_state.selected
                        and (rollback_state.selected.value or rollback_state.selected)
                )
                selection.queue(picker, finder, selected_key, { parent = true })
                picker:refresh(finder, { reset_prompt = false })
                if not selection.is_attached(picker) then
                    selection.restore_pending(picker)
                end
                if snapshot then
                    picker._sess_active_snapshot = snapshot
                end
                if type(picker._sess_active_commit_title) == "function" and snapshot then
                    picker._sess_active_commit_title(snapshot)
                end
                rows = next_rows
            end
        end)
        if not ok then
            selection.cancel(picker)
            if rollback_state then
                restore_state(picker, rollback_state)
            end
            fail(err)
        else
            rollback_state = nil
            picker._sess_active_refresh_warning = nil
        end
        if pending_resize and not stopped then
            pending_resize = false
            refresh()
        end
    end

    refresh = function()
        if stopped or refreshing then
            return
        end
        if not vim.api.nvim_buf_is_valid(prompt) then
            stop()
            return
        end
        if picker.prompt_win and not vim.api.nvim_win_is_valid(picker.prompt_win) then
            stop()
            return
        end

        refreshing = true
        picker._sess_active_refresh_generation = (picker._sess_active_refresh_generation or 0) + 1
        local generation = picker._sess_active_refresh_generation
        snapshot_at_refresh = picker._sess_active_snapshot
        rollback_state = capture_state(picker)
        local function complete(finder, next_rows, snapshot, unchanged)
            local completed, err = pcall(finish, generation, finder, next_rows, snapshot, unchanged)
            if not completed then
                fail(err)
            end
        end
        local function async_error(err)
            if
                not stopped
                and refreshing
                and generation == picker._sess_active_refresh_generation
            then
                fail(err)
            end
        end
        local ok, handle, next_rows, snapshot = pcall(
            generate,
            picker._sess_expanded,
            complete,
            async_error
        )
        if not ok then
            if rollback_state then
                restore_state(picker, rollback_state)
                rollback_state = nil
            end
            fail(handle)
        elseif type(handle) == "function" then
            cancel_refresh = handle
            if not refreshing then
                cancel_refresh = nil
            end
        elseif handle ~= nil then
            -- Backwards-compatible synchronous generator form.
            finish(generation, handle, next_rows, snapshot)
        end
    end

    -- A resize is a data-independent refresh: the same snapshot is rendered
    -- again using the result window's current screen-cell width.
    autocmds[#autocmds + 1] = vim.api.nvim_create_autocmd("VimResized", {
        callback = function()
            if refreshing then
                pending_resize = true
            else
                refresh()
            end
        end,
    })
    autocmds[#autocmds + 1] = vim.api.nvim_create_autocmd({ "BufHidden", "BufWipeout" }, {
        buffer = prompt,
        callback = stop,
    })
    if picker.prompt_win then
        autocmds[#autocmds + 1] = vim.api.nvim_create_autocmd("WinClosed", {
            pattern = tostring(picker.prompt_win),
            callback = stop,
        })
    end

    -- Hydrate after the lightweight picker is visible; the timer only schedules
    -- later status refreshes.
    refresh()

    if vim.async then
        task = vim.async.run(function()
            while not vim.async.is_closing() and not stopped do
                vim.async.sleep(poll_interval)
                if vim.async.is_closing() or stopped then
                    return
                end
                refresh()
            end
        end)
    else
        timer = assert(vim.uv.new_timer())
        timer:start(poll_interval, poll_interval, function()
            if stopped or refreshing or scheduled then
                return
            end
            scheduled = true
            vim.schedule(function()
                scheduled = false
                refresh()
            end)
        end)
    end

    return stop
end

return M
