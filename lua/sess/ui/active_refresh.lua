local M = {}

-- Poll only while this picker is open, and redraw only when its rows change.
-- This also observes explicit integration updates without global listeners.
function M.start(picker, generate, initial_rows)
    local prompt = picker.prompt_bufnr
    if not prompt or not vim.api.nvim_buf_is_valid(prompt) then
        return
    end

    local timer = assert(vim.uv.new_timer())
    local rows = initial_rows
    local stopped = false
    local cleanup
    local function stop()
        if stopped then
            return
        end
        stopped = true
        timer:stop()
        timer:close()
        if cleanup then
            pcall(vim.api.nvim_del_autocmd, cleanup)
        end
    end

    cleanup = vim.api.nvim_create_autocmd({ "BufHidden", "BufWipeout" }, {
        buffer = prompt,
        callback = stop,
    })
    timer:start(500, 500, vim.schedule_wrap(function()
        if stopped then
            return
        end
        if not vim.api.nvim_buf_is_valid(prompt) then
            stop()
            return
        end

        local ok, err = pcall(function()
            local finder, next_rows = generate(picker._sess_expanded)
            if not vim.deep_equal(rows, next_rows) then
                picker:refresh(finder, { reset_prompt = false })
                rows = next_rows
            end
        end)
        if not ok then
            stop()
            require("sess.log").warn("Active picker refresh failed: " .. tostring(err))
        end
    end))

    return stop
end

return M
