fixture.setup()

local api = require("sess.api")
local storage = require("sess.storage")

local ok, err, item = api.session.create(fixture.directory("healthy"))
assert(ok, err)
assert(storage.create("json"))
vim.fn.writefile({ "not json" }, fixture.root .. "/store/sessions/json/metadata.json")
assert(storage.create("version"))

local metadata = vim.deepcopy(item.metadata)
metadata.version = -1
assert(storage.write_metadata("version", metadata))

local success, list_err, sessions, diagnostics = api.session.list()
assert(success, list_err)
fixture.equal(1, #sessions)
fixture.equal(2, #diagnostics)
assert(diagnostics[1]:match("invalid JSON"))
assert(diagnostics[2]:match("unsupported session metadata version"))

local loaded, load_err = api.session.load("json")
assert(not loaded and load_err:match("invalid JSON"))
fixture.equal(item.id, api.state.current().id)
assert(api.session.get_by_name(item.metadata.name))
fixture.equal({ "not json" }, vim.fn.readfile(fixture.root .. "/store/sessions/json/metadata.json"))
