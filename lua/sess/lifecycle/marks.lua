local mark = require("sess.mark")
local storage = require("sess.storage")
local catalog = require("sess.session")
local target = require("sess.lifecycle.target")
local observer = require("sess.lifecycle.observer")

local M = {}

function M.set(destination, mark_value, options, context)
    local valid, err = mark.validate(mark_value)
    if not valid then
        return false, err
    end
    local callbacks = context.hooks
    if options and options.replace ~= nil and type(options.replace) ~= "boolean" then
        return false, "replace must be boolean"
    end
    local item, resolve_err, _, diagnostics = target.resolve(destination)
    if not item then
        return false, resolve_err
    end
    local marks, read_err = storage.read_marks()
    if not marks then
        return false, read_err
    end
    local previous_id = marks[mark_value]
    if previous_id and not (options and options.replace) then
        return false, "mark @" .. mark_value .. " is already assigned to session " .. previous_id
    end
    marks[mark_value] = item.id
    local written, write_err = storage.write_marks(marks)
    if not written then
        return false, write_err
    end
    return observer.finish("mark", item, context.hooks, diagnostics, {
        mark = mark_value, session_id = item.id, previous_id = previous_id,
    })
end

function M.clear(mark_value, context)
    local valid, err = mark.validate(mark_value)
    if not valid then
        return false, err
    end
    local marks, read_err = storage.read_marks()
    if not marks then
        return false, read_err
    end
    local id = marks[mark_value]
    if not id then
        return false, "mark not found: @" .. mark_value
    end
    local item, get_err = catalog.get(id)
    local diagnostics = {}
    if not item then
        diagnostics[1] = "cleared stale mark @" .. mark_value .. ": " .. (get_err or ("session not found: " .. id))
    end
    marks[mark_value] = nil
    local written, write_err = storage.write_marks(marks)
    if not written then
        return false, write_err
    end
    return observer.finish("unmark", item, context.hooks, diagnostics, {
        mark = mark_value, session_id = id,
    })
end

return M
