local editor = require("sess.editor")
local state = require("sess.state")

local M = {}

-- Ownership follows live views, not paths: a file or terminal may be shared.
-- Never stop arbitrary plugin jobs or infer ownership from a process's cwd.
local function retained_buffers(id)
    local current = state.get_current_session()
    local retained = {}
    for other_id, view in pairs(state.get_views()) do
        if other_id ~= id and (not current or other_id ~= current.id) then
            for buf in pairs(view.buffers) do
                retained[buf] = true
            end
        end
    end

    if not current or current.id ~= id then
        for buf in pairs(editor.capture().buffers) do
            retained[buf] = true
        end
    end

    return retained
end

local function describe(buf)
    if not vim.api.nvim_buf_is_valid(buf) then
        return nil
    end

    local terminal = vim.bo[buf].buftype == "terminal"
    local job = terminal and vim.b[buf].terminal_job_id or nil
    if job and vim.fn.jobwait({ job }, 0)[1] ~= -1 then
        job = nil
    end

    return {
        buf = buf,
        name = vim.api.nvim_buf_get_name(buf),
        modified = not terminal and vim.bo[buf].modified,
        changedtick = vim.api.nvim_buf_get_changedtick(buf),
        terminal = terminal,
        job = job,
    }
end

local function collect(item)
    local current = state.get_current_session()
    local view = current and current.id == item.id and editor.capture() or state.get_view(item.id)
    local retained = retained_buffers(item.id)
    local buffers = {}
    for buf in pairs(view and view.buffers or {}) do
        local record = not retained[buf] and describe(buf) or nil
        if record then
            table.insert(buffers, record)
        end
    end

    table.sort(buffers, function(a, b)
        return a.buf < b.buf
    end)

    return buffers
end

local function unchanged(expected, actual)
    if actual.terminal ~= expected.terminal or actual.name ~= expected.name then
        return false
    end

    -- Terminal output may continue while a prompt is open. Only job identity
    -- matters there; text-buffer edits invalidate the user's prior decision.
    if not actual.terminal and (actual.modified or expected.modified) then
        if actual.changedtick ~= expected.changedtick or actual.modified ~= expected.modified then
            return false
        end
    end

    return not actual.job or actual.job == expected.job
end

local function changed_error()
    return "session buffers or jobs changed during unload; retry to confirm the new state"
end

-- Confirmation is injected by UI adapters; the core never prompts. Both
-- decisions precede writes, snapshotting, buffer deletion and process stopping.
function M.prepare(item, confirm)
    local plan = { item = item, buffers = {}, paths = {} }
    local modified, jobs = {}, {}
    for _, record in ipairs(collect(item)) do
        plan.buffers[record.buf] = record
        if record.modified then
            table.insert(modified, record)
        end
        if record.job then
            table.insert(jobs, record)
        end
    end

    if #modified > 0 then
        if not confirm then
            return nil, "session has unsaved buffers; unload confirmation required"
        end

        local decision, paths = confirm({
            kind = "buffers",
            session = vim.deepcopy(item),
            buffers = vim.deepcopy(modified),
        })
        if decision ~= "save" and decision ~= "discard" then
            return nil, "unload cancelled"
        end
        if paths ~= nil and type(paths) ~= "table" then
            return nil, "save paths must be a table keyed by buffer number"
        end

        plan.decision, plan.paths = decision, paths or {}
    end

    if #jobs > 0 then
        if not confirm then
            return nil, "session has running terminal jobs; unload confirmation required"
        end
        local decision = confirm({
            kind = "jobs",
            session = vim.deepcopy(item),
            buffers = vim.deepcopy(jobs),
        })
        if decision ~= "stop" then
            return nil, "unload cancelled"
        end
    end

    local ok, err = M.validate(plan)
    if not ok then
        return nil, err
    end

    return plan
end

function M.validate(plan)
    for _, actual in ipairs(collect(plan.item)) do
        local expected = plan.buffers[actual.buf]
        if not expected or not unchanged(expected, actual) then
            return false, changed_error()
        end
    end

    return true
end

-- A failed write aborts before stopping any job or deleting any buffer. Earlier
-- successful writes are not reversible, just as with :wall.
function M.save_buffers(plan)
    if plan.decision ~= "save" then
        return true
    end

    local buffers = vim.tbl_keys(plan.buffers)
    table.sort(buffers)
    for _, buf in ipairs(buffers) do
        local expected = plan.buffers[buf]
        if expected.modified and not retained_buffers(plan.item.id)[buf] then
            local actual = describe(buf)
            if actual then
                if not unchanged(expected, actual) then
                    return false, changed_error()
                end

                local path = plan.paths[buf]
                if expected.name == "" and (type(path) ~= "string" or vim.trim(path) == "") then
                    return false, "a save path is required for unnamed buffer " .. buf
                end

                local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
                    vim.cmd({
                        cmd = "write",
                        args = expected.name == "" and { path } or {},
                        magic = { file = false, bar = false },
                    })
                end)
                if not ok then
                    return false, "failed to save buffer " .. buf .. ": " .. tostring(err)
                end

                actual = describe(buf)
                if actual and actual.terminal then
                    return false, changed_error()
                end
                if actual and actual.modified then
                    return false, "buffer " .. buf .. " still has unsaved changes"
                end
                if actual then
                    plan.buffers[buf] = actual
                end
            end
        end
    end

    return M.validate(plan)
end

-- Deletion/termination cannot be rolled back. Recheck each buffer immediately
-- before forcing deletion so callbacks cannot expand the user's consent.
function M.close(plan)
    local buffers = vim.tbl_keys(plan.buffers)
    table.sort(buffers)
    for _, buf in ipairs(buffers) do
        if not retained_buffers(plan.item.id)[buf] then
            local actual = describe(buf)
            if actual then
                local expected = plan.buffers[buf]
                if not unchanged(expected, actual) then
                    return false, changed_error()
                end

                -- Force is only for explicitly discarded edits or an approved
                -- live terminal. Neovim stops the terminal job on buffer wipe.
                local force = (actual.modified and plan.decision == "discard") or actual.job ~= nil
                local ok, err = pcall(vim.api.nvim_buf_delete, buf, { force = force })
                if not ok then
                    return false, "failed to close buffer " .. buf .. ": " .. tostring(err)
                end
            end
        end
    end

    return true
end

return M
