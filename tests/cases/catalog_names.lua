fixture.setup()

local catalog = require("sess.session")
local api = require("sess.api")

local ok, err, first = api.session.create(fixture.directory("one/project"))
assert(ok, err)
fixture.equal("project", first.metadata.name)

local second
ok, err, second = api.session.create(fixture.directory("two/project"))
assert(ok, err)
fixture.equal("project (2)", second.metadata.name)

local cwd = fixture.directory("three/project")
local prepared = assert(catalog.prepare_create({ cwd = cwd }))
fixture.equal("project (3)", prepared.metadata.name)
fixture.equal(2, #catalog.list()) -- Preparation does not persist a record.

local item
item, err = catalog.prepare_create({ cwd = cwd, name = "PROJECT" })
assert(not item and err:match("name already exists"), tostring(err))
item, err = catalog.prepare_create({ cwd = first.metadata.cwd, name = "other" })
assert(not item and err:match("directory"), tostring(err))
ok, err = api.session.rename(second, "PROJECT")
assert(not ok and err:match("name already exists"), tostring(err))
fixture.equal(second, api.state.current())

-- Renaming to the same name with different casing does not conflict with self.
ok, err, first = api.session.rename(first, "PROJECT")
assert(ok, err)
fixture.equal("PROJECT", first.metadata.name)
fixture.equal("project (3)", assert(catalog.prepare_create({ cwd = cwd })).metadata.name)
