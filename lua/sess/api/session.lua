local catalog = require("sess.session")
local opts = require("sess.api.opts")
local scope = require("sess.lifecycle.operation_scope")
local create = require("sess.lifecycle.create")
local load = require("sess.lifecycle.load")
local mutations = require("sess.lifecycle.mutations")
local unload = require("sess.lifecycle.unload")
local save = require("sess.lifecycle.save")
local marks = require("sess.lifecycle.marks")

local M = {}

-- Resolve configuration at the application boundary. Lifecycle modules receive
-- immutable operation context and never reach back into the public API.
local function context_for(options, allowed)
    if options == nil then
        return { hooks = opts.get().hooks }
    end
    if type(options) ~= "table" then
        return nil, "options must be a table"
    end

    for key in pairs(options) do
        if key ~= "hooks" and not (allowed and allowed[key]) then
            return nil, "unknown operation option: " .. tostring(key)
        end
    end

    if options.hooks ~= nil then
        local valid, err = opts.validate_hooks(options.hooks)
        if not valid then
            return nil, err
        end
    end

    return { hooks = vim.tbl_extend("force", opts.get().hooks, options.hooks or {}) }
end

local function invoke(operation, mutation, builder, context_position)
    return function(...)
        if not opts.is_setup() then
            return false, "sess.nvim is not initialized; call setup() first"
        end

        local args, count = { ... }, select("#", ...)
        local context, err = builder(unpack(args, 1, count))
        if not context then
            return false, err
        end
        args[context_position] = context

        return scope.wrap(operation, mutation)(unpack(args, 1, context_position))
    end
end

local function option_builder(position, allowed)
    return function(...)
        local args = { ... }
        return context_for(args[position], allowed)
    end
end

local default_context = function()
    return context_for(nil)
end

M.create = invoke(create.run, true, option_builder(2, { name = true, id = true }), 3)
M.load = invoke(load.run, true, option_builder(2), 3)
M.last = invoke(load.last, true, option_builder(1), 2)
M.save = function(...)
    if select("#", ...) > 0 then
        return false, "save() takes no arguments and saves only the current session"
    end
    if not opts.is_setup() then
        return false, "sess.nvim is not initialized; call setup() first"
    end
    local context = default_context()
    return scope.wrap(function() return save.save(context.hooks) end, true)()
end
M.unload = invoke(unload.run, true, function(destination, options)
    if type(destination) == "table" and destination.id == nil and destination.metadata == nil and options == nil then
        options = destination
    end
    return context_for(options, { confirm = true })
end, 3)
M.delete = invoke(mutations.delete, true, option_builder(2), 3)
M.restore = invoke(mutations.restore, true, option_builder(2), 3)
M.rename = invoke(mutations.rename, true, default_context, 3)
M.toggle_pin = invoke(mutations.toggle_pin, true, default_context, 2)
M.set_mark = invoke(marks.set, true, option_builder(3, { replace = true }), 4)
M.clear_mark = invoke(marks.clear, true, default_context, 2)

local function query(operation)
    return function(...)
        if not opts.is_setup() then
            return false, "sess.nvim is not initialized; call setup() first"
        end
        return scope.wrap(operation, false)(...)
    end
end

M.resolve = query(function(target)
    local item, err, reason, diagnostics = catalog.resolve(target)
    return item ~= nil, err, item, reason, diagnostics
end)

M.list = query(function()
    local items, err, diagnostics = catalog.list()
    return err == nil, err, items, diagnostics
end)

M.get = query(function(target)
    local item, err, _, diagnostics = catalog.resolve(target)
    return item ~= nil, err, item, diagnostics or {}
end)

M.get_by_mark = query(function(mark)
    local item, err, diagnostics = catalog.get_by_mark(mark)
    return item ~= nil, err, item, diagnostics
end)

M.list_marks = query(function()
    local entries, err, diagnostics = catalog.list_marks()
    return err == nil, err, entries, diagnostics
end)

M.list_deleted = query(function()
    local items, err, diagnostics = catalog.list_deleted()
    return err == nil, err, items, diagnostics
end)

for name, catalog_query in pairs({
    get_by_id = catalog.get,
    get_by_name = catalog.get_by_name,
    get_by_path = catalog.get_by_path,
}) do
    M[name] = query(function(value)
        local item, err, diagnostics = catalog_query(value)

        if name == "get_by_name" or name == "get_by_path" then
            return err == nil, err, item, diagnostics
        end

        return err == nil, err, item
    end)
end

return M
