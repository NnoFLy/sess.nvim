local M = {}

local selection = require("telescope._extensions.sess.selection")

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
    local pending_resize = false
    local snapshot_at_refresh
    local autocmds = {}

    local function stop()
        if stopped then
            return
        end
        stopped = true
        refreshing = false
        pending_resize = false
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

    local refresh

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
            if pending_resize and not stopped then
                pending_resize = false
                refresh()
            end
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
                local selected_key = selection.current_key(picker)
                selection.queue(picker, finder, selected_key, { parent = true })
                picker:refresh(finder, { reset_prompt = false })
                if not selection.is_attached(picker) then
                    selection.restore_pending(picker)
                end
                rows = next_rows
            end
        end)
        if not ok then
            fail(err)
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
