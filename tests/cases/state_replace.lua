fixture.setup()

local api = require("sess.api")

local ok, err, item = api.session.create(fixture.directory("project"))
assert(ok, err)
require("sess.state").set_prev_session(item)
assert(api.session.rename(item, "renamed"))
fixture.equal("renamed", api.state.prev().metadata.name)
fixture.equal("renamed", api.state.current().metadata.name)
fixture.equal("renamed", api.state.active()[1].metadata.name)
fixture.equal("renamed", vim.g.sess_current_session)
assert(api.session.toggle_pin(item))
fixture.equal(true, api.state.active()[1].metadata.pinned)

local copy = api.state.current()
copy.metadata.name = "mutated"
fixture.equal("renamed", api.state.current().metadata.name)
