local catalog = require("sess.session")
local opts = require("sess.api.opts")
local transaction = require("sess.lifecycle.transaction")
local create = require("sess.lifecycle.create")
local load = require("sess.lifecycle.load")
local mutations = require("sess.lifecycle.mutations")
local unload = require("sess.lifecycle.unload")
local save = require("sess.lifecycle.save")

local M = {}

-- This module is intentionally only the public API surface. Lifecycle policy is
-- split between transaction, observer, target, save, and operation modules.
M.create = transaction.wrap(create.run, true)
M.load = transaction.wrap(load.run, true)
M.last = transaction.wrap(load.last, true)
M.save = transaction.wrap(save.save, true)
M.unload = transaction.wrap(unload.run, true)
M.delete = transaction.wrap(mutations.delete, true)
M.restore = transaction.wrap(mutations.restore, true)
M.rename = transaction.wrap(mutations.rename, true)
M.toggle_pin = transaction.wrap(mutations.toggle_pin, true)

local function query(operation)
    return transaction.wrap(operation, false)
end

M.resolve = query(function(target)
    local item, err, reason, diagnostics = catalog.resolve(target)
    return item ~= nil, err, item, reason, diagnostics
end)

M.list = query(function()
    local items, err, diagnostics = catalog.list()
    return err == nil, err, items, diagnostics
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
