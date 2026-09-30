local M = {}

local POLL_INTERVAL = 1000

-- Poll only while this picker is open, and redraw only when its rows change.
-- The generator receives a completion callback and may yield between probes.
function M.start(picker, generate, initial_rows)
    local prompt = picker.prompt_bufnr
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
    local cleanup

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
        if cleanup then
            pcall(vim.api.nvim_del_autocmd, cleanup)
        end
    end

    local function fail(err)
        stop()
        require("sess.log").warn("Active picker refresh failed: " .. tostring(err))
    end

    local function finish(finder, next_rows)
        if stopped or not refreshing then
            return
        end
        refreshing = false
        cancel_refresh = nil

        local ok, err = pcall(function()
            if not vim.deep_equal(rows, next_rows) then
                picker:refresh(finder, { reset_prompt = false })
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

        refreshing = true
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

    cleanup = vim.api.nvim_create_autocmd({ "BufHidden", "BufWipeout" }, {
        buffer = prompt,
        callback = stop,
    })

    if vim.async then
        task = vim.async.run(function()
            while not vim.async.is_closing() and not stopped do
                vim.async.sleep(POLL_INTERVAL)
                if vim.async.is_closing() or stopped then
                    return
                end
                refresh()
            end
        end)
    else
        timer = assert(vim.uv.new_timer())
        timer:start(POLL_INTERVAL, POLL_INTERVAL, function()
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
