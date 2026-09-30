local api = require("sess.api")
local log = require("sess.log")
local mark_rules = require("sess.mark")

local M = {}

-- Command syntax requires @; Lua navigation and picker input may omit it.
function M.parse(value, require_prefix)
    if type(value) ~= "string" then
        return nil, "mark is required"
    end
    if value:sub(1, 1) == "@" then
        value = value:sub(2)
    elseif require_prefix then
        return nil, "mark must use @ followed by one lowercase ASCII letter or digit"
    end
    local valid, err = mark_rules.validate(value)
    return valid and value or nil, err
end

-- Confirmation belongs here, never in the prompt-free lifecycle.
function M.assign(target, mark)
    local valid, validation_err = mark_rules.validate(mark)
    if not valid then
        return false, validation_err
    end
    local ok, err, entries, diagnostics = api.session.list_marks()
    if not ok then
        return false, err
    end
    local replace = false
    for _, entry in ipairs(entries) do
        if entry.mark == mark then
            local owner = entry.session and entry.session.metadata.name or (entry.id .. " (stale)")
            if vim.fn.confirm("Replace mark @" .. mark .. " on " .. owner .. "?", "&Yes\n&No", 2) ~= 1 then
                return false, "mark cancelled"
            end
            replace = true
            break
        end
    end
    local assigned, assign_err, item, result_diagnostics = api.session.set_mark(target, mark, { replace = replace })
    if assigned then
        vim.list_extend(result_diagnostics, diagnostics or {})
    end
    return assigned, assign_err, item, result_diagnostics
end

function M.report(ok, err, diagnostics)
    if ok then
        log.diagnostics(diagnostics)
    elseif err == "mark cancelled" then
        log.info("Mark cancelled")
    else
        log.error(err)
    end
    return ok
end

local function read_mark(value)
    if value == nil then
        local ok, key = pcall(vim.fn.getcharstr)
        if not ok then
            return nil
        end
        value = key
    end
    if value == "\27" then
        return nil
    end
    local mark, err = M.parse(value)
    if not mark then
        log.error(err)
    end
    return mark
end

function M.set_mark(value)
    local mark = read_mark(value)
    if not mark then
        return false
    end
    local ok, assigned, assign_err, _, diagnostics = pcall(M.assign, nil, mark)
    if not ok then
        log.error(tostring(assigned))
        return false
    end
    return M.report(assigned, assign_err, diagnostics)
end

function M.goto_mark(value)
    local mark = read_mark(value)
    if not mark then
        return false
    end
    local called, ok, load_err, _, diagnostics = pcall(api.session.load, "@" .. mark)
    if not called then
        log.error(tostring(ok))
        return false
    end
    if ok then
        return M.report(ok, load_err, diagnostics)
    end

    if load_err ~= "mark not found: @" .. mark then
        return M.report(false, load_err, diagnostics)
    end

    local assign_called, assigned, assign_err, _, assign_diagnostics = pcall(M.assign, nil, mark)
    if not assign_called then
        log.error(tostring(assigned))
        return false
    end
    if not assigned then
        return M.report(false, assign_err, assign_diagnostics)
    end

    log.info("Created mark @" .. mark .. " on current session")
    return M.report(true, nil, assign_diagnostics)
end

return M
