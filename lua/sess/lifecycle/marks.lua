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

function M.clear(mark_value, options, context)
    local valid, err = mark.validate(mark_value)
    if not valid then
        return false, err
    end
    if options ~= nil and type(options) ~= "table" then
        return false, "mark clear options must be a table"
    end
    local expected_id = options and options.expected_id
    if expected_id ~= nil then
        valid, err = storage.validate_id(expected_id)
        if not valid then
            return false, err
        end
    end

    local marks, read_err = storage.read_marks()
    if not marks then
        return false, read_err
    end
    local id = marks[mark_value]
    if not id then
        return false, "mark not found: @" .. mark_value
    end
    if expected_id ~= nil and id ~= expected_id then
        return false, "mark @" .. mark_value .. " changed before it could be cleared"
    end

    local item, get_err, reason = catalog.get(id)
    if get_err and reason ~= "not-found" then
        return false, get_err
    end
    local diagnostics = {}
    if not item then
        diagnostics[1] = "cleared stale mark @"
            .. mark_value
            .. ": "
            .. (get_err or ("session not found: " .. id))
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

-- Move an assignment in one registry read/write pair. The source owner may be
-- stale; stale assignments remain movable and retain their original id.
function M.move(from_mark, to_mark, options, context)
    local valid, err = mark.validate(from_mark)
    if not valid then
        return false, err
    end
    valid, err = mark.validate(to_mark)
    if not valid then
        return false, err
    end
    if from_mark == to_mark then
        return false, "source and destination marks must differ"
    end
    options = options or {}
    if type(options) ~= "table" then
        return false, "mark move options must be a table"
    end
    if options.replace ~= nil and type(options.replace) ~= "boolean" then
        return false, "replace must be boolean"
    end
    if options.check_destination ~= nil and type(options.check_destination) ~= "boolean" then
        return false, "check_destination must be boolean"
    end
    if options.expected_id ~= nil then
        valid, err = storage.validate_id(options.expected_id)
        if not valid then
            return false, err
        end
    end
    if options.expected_destination ~= nil then
        valid, err = storage.validate_id(options.expected_destination)
        if not valid then
            return false, err
        end
    end

    local marks, read_err = storage.read_marks()
    if not marks then
        return false, read_err
    end
    local owner_id = marks[from_mark]
    if not owner_id then
        return false, "mark not found: @" .. from_mark
    end
    if options.expected_id ~= nil and owner_id ~= options.expected_id then
        return false, "mark @" .. from_mark .. " changed before it could be moved"
    end
    local previous_id = marks[to_mark]
    if options.check_destination and previous_id ~= options.expected_destination then
        return false, "destination mark changed before it could be assigned"
    end
    if previous_id and not options.replace then
        return false, "mark @" .. to_mark .. " is already assigned to session " .. previous_id
    end

    local item, owner_err, reason = catalog.get(owner_id)
    if owner_err and reason ~= "not-found" then
        return false, owner_err
    end
    local diagnostics = {}
    if not item then
        diagnostics[1] = "moved stale mark @"
            .. from_mark
            .. ": "
            .. (owner_err or ("session not found: " .. owner_id))
    end

    marks[from_mark] = nil
    marks[to_mark] = owner_id
    local written, write_err = storage.write_marks(marks)
    if not written then
        return false, write_err
    end

    return observer.finish("mark", item, context.hooks, diagnostics, {
        mark = to_mark,
        previous_mark = from_mark,
        session_id = owner_id,
        previous_id = previous_id,
    })
end

-- Restore a popup mutation only if every registry entry still has the value
-- produced by that mutation. This keeps undo from overwriting external work.
function M.restore(changes, context)
    if type(changes) ~= "table" or not vim.islist(changes) or #changes == 0 then
        return false, "mark restore changes must be a non-empty list"
    end

    local seen = {}
    for _, change in ipairs(changes) do
        if type(change) ~= "table" then
            return false, "mark restore change must be a table"
        end
        local valid, err = mark.validate(change.mark)
        if not valid then
            return false, err
        end
        if seen[change.mark] then
            return false, "mark restore contains duplicate marks"
        end
        seen[change.mark] = true
        for _, id in ipairs({ change.expected, change.value }) do
            if id ~= nil then
                valid, err = storage.validate_id(id)
                if not valid then
                    return false, err
                end
            end
        end
    end

    local marks, read_err = storage.read_marks()
    if not marks then
        return false, read_err
    end
    for _, change in ipairs(changes) do
        if marks[change.mark] ~= change.expected then
            return false, "mark state changed since popup mutation"
        end
    end

    local owner_id
    for _, change in ipairs(changes) do
        marks[change.mark] = change.value
        owner_id = owner_id or change.value
    end

    local item
    local diagnostics = {}
    if owner_id then
        local owner_err, reason
        item, owner_err, reason = catalog.get(owner_id)
        if owner_err and reason ~= "not-found" then
            return false, owner_err
        end
        if not item then
            diagnostics[1] = "restored stale mark owner: " .. owner_id
        end
    end

    local written, write_err = storage.write_marks(marks)
    if not written then
        return false, write_err
    end

    local operation = owner_id and "mark" or "unmark"
    local primary = changes[1]
    return observer.finish(operation, item, context.hooks, diagnostics, {
        mark = primary.mark,
        session_id = owner_id,
    })
end

return M
