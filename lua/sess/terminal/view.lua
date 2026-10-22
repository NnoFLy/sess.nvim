local backend = require("sess.terminal.backend")
local editor = require("sess.editor")
local M = {}
local views = {}
local clients = {}

local function report(message)
    require("sess.log").warn(message)
end

local function cleanup(view)
    if view.cleaned then
        return
    end
    view.cleaned = true
    clients[view] = nil
    local ok, err = backend.cleanup_attachment(view.attachment)
    if not ok then
        report(
            "terminal attachment cleanup failed (execution " .. view.id .. "): " .. tostring(err)
        )
    end
end

local function exited(view)
    if view.starting or view.exit_code == nil then
        return
    end
    if view.accepted and not view.closing and view.exit_code ~= 0 and not view.reported then
        view.reported = true
        report(
            "terminal attachment failed (exit "
                .. view.exit_code
                .. "); execution "
                .. view.id
                .. " was not stopped"
        )
    end
    cleanup(view)
end

-- Buffer names and b:variables are display data, never authority for teardown.
-- Keep the job identity even after exit, until this exact buffer is wiped.
function M.identity(buf)
    local view = views[buf]
    if not view or not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "terminal" then
        return nil
    end
    local channel = vim.api.nvim_get_chan_info(view.job_id)
    if next(channel) ~= nil and channel.buffer ~= buf then
        return nil
    end
    return view.job_id
end

local function selected(win, buf)
    return vim.api.nvim_win_is_valid(win)
        and vim.api.nvim_get_current_win() == win
        and vim.api.nvim_win_get_buf(win) == buf
        and vim.api.nvim_get_current_buf() == buf
end

local function attached(view, win, buf)
    local channel = vim.api.nvim_get_chan_info(view.job_id)
    return selected(win, buf)
        and vim.api.nvim_buf_is_valid(buf)
        and vim.bo[buf].buftype == "terminal"
        and not vim.bo[buf].modified
        and vim.api.nvim_buf_get_name(buf) == view.name
        and channel.mode == "terminal"
        and channel.buffer == buf
end

local function empty(buf, tick)
    return vim.api.nvim_buf_is_valid(buf)
        and vim.bo[buf].buftype == ""
        and not vim.bo[buf].modified
        and vim.api.nvim_buf_get_name(buf) == ""
        and vim.api.nvim_buf_get_changedtick(buf) == tick
        and vim.api.nvim_buf_line_count(buf) == 1
        and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
end

local function dispose(view, buf, tick)
    if not buf or not vim.api.nvim_buf_is_valid(buf) then
        return
    end
    -- Callbacks may have adopted the buffer, populated it, or started another
    -- job. Never force deletion or infer client ownership from such a channel.
    for _, channel in ipairs(vim.api.nvim_list_chans()) do
        if channel.buffer == buf then
            return
        end
    end
    local terminal = views[buf] == view
        and vim.bo[buf].buftype == "terminal"
        and not vim.bo[buf].modified
        and vim.api.nvim_buf_get_name(buf) == view.name
    if terminal or empty(buf, tick) then
        vim.api.nvim_buf_delete(buf, { force = false })
    end
end

function M.open(execution)
    local win, source = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
    if editor.is_transient_window(win) then
        return nil, "cannot open a terminal attachment in a transient UI window"
    end
    local attachment, err = backend.prepare_attachment(execution.id)
    if not attachment then
        return nil, err
    end

    local view = { id = execution.id, attachment = attachment, starting = true }
    local buf, tick
    local attempted, not_started = false, false
    local ok, result = editor.protected(function()
        if not selected(win, source) then
            error("invoking window or buffer changed before terminal attachment")
        end
        buf = vim.api.nvim_create_buf(true, false)
        tick = vim.api.nvim_buf_get_changedtick(buf)
        vim.bo[buf].bufhidden = "hide"
        vim.api.nvim_create_autocmd("BufWipeout", {
            buffer = buf,
            once = true,
            callback = function()
                view.closing = true
                views[buf] = nil
            end,
        })
        vim.api.nvim_win_set_buf(win, buf)
        if not selected(win, buf) or not empty(buf, tick) then
            error("terminal attachment buffer was redirected or changed by callbacks")
        end
        attempted = true
        local job = vim.fn.jobstart(attachment.argv, {
            term = true,
            env = attachment.env,
            on_exit = function(job_id, code)
                -- This callback belongs to this spawn, unlike channels discovered
                -- after a throwing TermOpen callback, which may belong to anyone.
                view.job_id, view.exit_code = job_id, code
                vim.schedule(function()
                    exited(view)
                end)
            end,
        })
        not_started = job <= 0
        if not_started then
            error("terminal attachment job could not start: " .. job)
        end
        local channel = vim.api.nvim_get_chan_info(job)
        if channel.buffer ~= buf or channel.mode ~= "terminal" then
            error("terminal attachment channel does not belong to its buffer")
        end
        view.job_id = job
        clients[view] = true
        views[buf] = view
        -- mksession must emit only an inert file reference, never :terminal
        -- with either a launch command or an automatically replayed attachment.
        view.name = "sess-terminal://" .. execution.id .. "/" .. attachment.helper_id
        vim.api.nvim_buf_set_name(buf, view.name)
        local status = vim.fn.jobwait({ job }, 0)[1]
        if view.exit_code ~= nil or status ~= -1 then
            error(
                "terminal attachment client exited during startup: "
                    .. tostring(view.exit_code or status)
            )
        end
        if not attached(view, win, buf) then
            error("terminal attachment window or buffer changed during startup")
        end
        return { id = execution.id, execution = execution, bufnr = buf, job_id = job }
    end)
    view.starting = false
    -- Transient-owner resume callbacks also run inside protected(), and can
    -- drain an exit after the inner startup checks have finished.
    if ok and (view.exit_code ~= nil or vim.fn.jobwait({ view.job_id }, 0)[1] ~= -1) then
        ok, result =
            false, "terminal attachment client exited during startup: " .. tostring(view.exit_code)
    end
    if ok and not attached(view, win, buf) then
        ok, result = false, "terminal attachment identity changed during startup"
    end
    if not ok then
        view.closing = true
        local cleaned, cleanup_err = editor.protected(function()
            if view.job_id then
                clients[view] = true
                if view.exit_code == nil then
                    vim.fn.jobstop(view.job_id)
                    vim.fn.jobwait({ view.job_id }, 1000)
                end
                exited(view)
            elseif not attempted or not_started then
                cleanup(view)
            else
                -- jobstart can throw after spawning. Without its returned ID or
                -- on_exit, stopping a discovered channel could kill callback work.
                result = tostring(result) .. "; uncertain attachment client/helper retained"
            end
            dispose(view, buf, tick)
        end)
        if not cleaned then
            result = tostring(result) .. "; attachment cleanup failed: " .. tostring(cleanup_err)
        end
        return nil, tostring(result)
    end
    view.accepted = true
    exited(view)
    return result
end

vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
        -- Neovim owns only these clients. Wait for their exit before unlinking
        -- helpers; killing a helper while its client lives can retarget it.
        for view in pairs(clients) do
            view.closing = true
            if not view.cleaned then
                if vim.fn.jobwait({ view.job_id }, 0)[1] == -1 then
                    vim.fn.jobstop(view.job_id)
                end
                if vim.fn.jobwait({ view.job_id }, 1000)[1] ~= -1 then
                    cleanup(view)
                else
                    report("terminal client did not exit; helper retained for " .. view.id)
                end
            end
        end
    end,
})

return M
