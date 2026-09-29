fixture.setup()

local api = require("sess.api")
local storage = require("sess.storage")

local ok, err, first = api.session.create(fixture.directory("first"), { name = "duplicate" })
assert(ok, err)
local second_ok, second_err, second = api.session.create(fixture.directory("second"), { name = "other" })
assert(second_ok, second_err)

local second_metadata = assert(storage.read_metadata(second.id))
second_metadata.name = first.metadata.name
second_metadata.cwd = first.metadata.cwd
assert(storage.write_metadata(second.id, second_metadata))

local found, lookup_err, item, diagnostics = api.session.get_by_name("duplicate")
assert(not found)
assert(lookup_err:match("ambiguous"), lookup_err)
assert(item == nil)
assert(type(diagnostics) == "table")

found, lookup_err, item, diagnostics = api.session.get_by_path(first.metadata.cwd)
assert(not found)
assert(lookup_err:match("ambiguous"), lookup_err)
assert(item == nil)
assert(type(diagnostics) == "table")
