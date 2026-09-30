local catalog = require("sess.session")
local editor = require("sess.editor")
local state = require("sess.state")
local storage = require("sess.storage")
local observer = require("sess.lifecycle.observer")
local target = require("sess.lifecycle.target")

local M = {}

-- Storage owns temporary paths and replacement; the editor only writes to the
-- path it receives.
function M.snapshot(item)
    local previous = vim.v.this_session
    local ok, err = storage.replace_snapshot(item.id, function(path)
        return editor.write_snapshot(path, item)
    end)
    if ok then
        local path, path_err = storage.get_session_path(item.id)
        if not path then
            return false, path_err
        end
        vim.v.this_session = path
    else
        vim.v.this_session = previous
    end
    return ok, err
end

-- Usage metadata is best-effort only after the snapshot/editor action succeeds.
function M.touch(item, diagnostics)
    local called, updated, err = pcall(catalog.touch, item.id)
    if not called then
        err, updated = updated, nil
    end

    if err then
        table.insert(diagnostics, "metadata update failed: " .. tostring(err))
    end

    return updated or item
end

-- Internal saves share the caller's guard and hook overrides.
function M.current(callbacks)
    local item, err = target.resolve()
    if not item then
        return false, err
    end

    local view = editor.capture()
    local ok, save_err = M.snapshot(item)
    if not ok then
        return false, save_err
    end

    view.this_session = vim.v.this_session
    state.set_view(item.id, view)

    local diagnostics = {}
    item = M.touch(item, diagnostics)
    state.replace(item)

    return observer.finish("save", item, callbacks, diagnostics)
end

function M.outgoing(callbacks)
    if not state.get_current_session() then
        return true, nil, nil, {}
    end

    local ok, err, item, diagnostics = M.current(callbacks)
    if not ok then
        return false, "failed to save outgoing session: " .. tostring(err)
    end

    return true, nil, item, diagnostics
end

function M.save(callbacks, ...)
    if select("#", ...) > 0 then
        return false, "save() takes no arguments and saves only the current session"
    end

    return M.current(callbacks)
end

return M
