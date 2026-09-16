fixture.setup()

local api = require("sess.api")

local ok, err, item = api.session.create(fixture.directory("healthy"), { name = "healthy" })
assert(ok, err)
assert(require("sess.storage").create("broken"))

local found, lookup_err, healthy = api.session.get_by_name("healthy")
assert(found, lookup_err)
fixture.equal(item.id, healthy.id)

local listed, list_err, items, diagnostics = api.session.list()
assert(listed, list_err)
fixture.equal(1, #items)
fixture.equal(1, #diagnostics)
assert(diagnostics[1]:match("broken"))
assert(api.session.get_by_path(item.metadata.cwd))
assert(api.session.save())
assert(api.session.toggle_pin("healthy"))
assert(api.session.unload())
assert(api.session.load("healthy"))

local renamed, rename_err = api.session.rename(item, "renamed")
assert(not renamed and rename_err:match("cannot verify uniqueness"))

local created, create_err = api.session.create(fixture.directory("new"), { name = "new" })
assert(not created and create_err:match("cannot verify uniqueness"))

local picker_items, picker_err, picker_diagnostics = api.items.get_items()
assert(not picker_err)
fixture.equal(1, #picker_items)
fixture.equal(diagnostics, picker_diagnostics)

local storage = require("sess.storage")
assert(storage.exists("broken"))

-- A failed directory scan is fatal, not an empty or partially healthy store.
local readdir = vim.fn.readdir
vim.fn.readdir = function()
    error("injected read failure")
end

local success, read_err = api.session.list()
assert(not success and read_err:match("injected read failure"))

local saved, save_err = api.session.load("healthy")
assert(not saved and save_err:match("injected read failure"))
vim.fn.readdir = readdir
