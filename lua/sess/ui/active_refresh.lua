local M = {}

local DEFAULT_POLL_INTERVAL = 1000

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
    local snapshot_at_refresh
    local autocmds = {}

    local function stop()
        if stopped then
            return
        end
        stopped = true
        refreshing = false
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
        -- Keep the last committed rows and let the next poll retry it.
        refreshing = false
        cancel_refresh = nil
        require("sess.log").warn("Active picker refresh failed: " .. tostring(err))
    end

    local function finish(finder, next_rows, snapshot)
        if stopped or not refreshing then
            return
        end
        refreshing = false
        cancel_refresh = nil

        -- Ignore probes started before a user mutation replaced the cached
        -- snapshot while the probe was yielding.
        if
            snapshot
            and snapshot_at_refresh
            and picker._sess_active_snapshot ~= snapshot_at_refresh
        then
            return
        end

        local ok, err = pcall(function()
            -- Collapsed rows can stay unchanged while a session status changes.
            local snapshot_changed = snapshot ~= nil
                and not vim.deep_equal(picker._sess_active_snapshot, snapshot)
            if snapshot then
                picker._sess_active_snapshot = snapshot
            end
            if snapshot_changed or not vim.deep_equal(rows, next_rows) then
                local selected_key
                if type(picker.get_selection) == "function" then
                    local selected = picker:get_selection()
                    local value = selected and selected.value or selected
                    if value then
                        local id = value.id or value.session_id
                        if id then
                            selected_key = {
                                id = id,
                                kind = value.kind,
                                agent_id = value.agent_id,
                            }
                        end
                    end
                end
                picker:refresh(finder, { reset_prompt = false })
                if selected_key and type(picker.set_selection) == "function" then
                    local restored = false
                    for index, row in ipairs(next_rows or {}) do
                        local value = row.value or row
                        local id = value.id or value.session_id
                        if
                            id == selected_key.id
                            and value.kind == selected_key.kind
                            and value.agent_id == selected_key.agent_id
                        then
                            pcall(picker.set_selection, picker, index)
                            restored = true
                            break
                        end
                    end
                    if not restored then
                        -- A disappearing agent can no longer be selected. Keep
                        -- the parent session selected when it remains visible;
                        -- otherwise choose the first valid row.
                        for index, row in ipairs(next_rows or {}) do
                            local value = row.value or row
                            if
                                value.session_id == selected_key.id
                                and value.kind == "session"
                            then
                                pcall(picker.set_selection, picker, index)
                                restored = true
                                break
                            end
                        end
                        if not restored and #(next_rows or {}) > 0 then
                            pcall(picker.set_selection, picker, 1)
                        end
                    end
                end
                rows = next_rows
            end
        end)
        if not ok then
            fail(err)
        end
    end

    local function refresh()
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
        snapshot_at_refresh = picker._sess_active_snapshot
        local ok, handle, next_rows = pcall(generate, picker._sess_expanded, finish)
        if not ok then
            fail(handle)
        elseif type(handle) == "function" then
            cancel_refresh = handle
            if not refreshing then
                cancel_refresh = nil
            end
        elseif handle ~= nil then
            -- Backwards-compatible synchronous generator form.
            finish(handle, next_rows)
        end
    end

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
