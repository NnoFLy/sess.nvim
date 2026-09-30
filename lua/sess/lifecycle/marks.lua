local storage = require("sess.storage")
local catalog = require("sess.session")
local target = require("sess.lifecycle.target")
local observer = require("sess.lifecycle.observer")

local M = {}

function M.set(destination, mark, options)
    local valid, err = storage.validate_mark(mark)
    if not valid then
        return false, err
    end
    local callbacks, hook_err = observer.hooks(options, { replace = true })
    if not callbacks then
        return false, hook_err
    end
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
    local previous_id = marks[mark]
    if previous_id and not (options and options.replace) then
        return false, "mark @" .. mark .. " is already assigned to session " .. previous_id
    end
    marks[mark] = item.id
    local written, write_err = storage.write_marks(marks)
    if not written then
        return false, write_err
    end
    return observer.finish("mark", item, callbacks, diagnostics, {
        mark = mark, session_id = item.id, previous_id = previous_id,
    })
end

function M.clear(mark)
    local valid, err = storage.validate_mark(mark)
    if not valid then
        return false, err
    end
    local marks, read_err = storage.read_marks()
    if not marks then
        return false, read_err
    end
    local id = marks[mark]
    if not id then
        return false, "mark not found: @" .. mark
    end
    local item, get_err = catalog.get(id)
    local diagnostics = {}
    if not item then
        diagnostics[1] = "cleared stale mark @" .. mark .. ": " .. (get_err or ("session not found: " .. id))
    end
    marks[mark] = nil
    local written, write_err = storage.write_marks(marks)
    if not written then
        return false, write_err
    end
    return observer.finish("unmark", item, require("sess.api.opts").get().hooks, diagnostics, {
        mark = mark, session_id = id,
    })
end

return M
