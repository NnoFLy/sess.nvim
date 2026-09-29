fixture.setup()

local api = require("sess.api")
local storage = require("sess.storage")
local state = require("sess.state")

local _, _, a = api.session.create(fixture.directory("a"), { name = "a" })
local _, _, b = api.session.create(fixture.directory("b"), { name = "b" })
local _, _, c = api.session.create(fixture.directory("c"), { name = "c" })

-- Make the persisted ordering explicit, independent of wall-clock resolution.
for item, last_used_at in pairs({ [a.id] = 100, [b.id] = 200, [c.id] = 300 }) do
    local metadata = assert(storage.read_metadata(item))
    metadata.last_used_at = last_used_at
    assert(storage.write_metadata(item, metadata))
end

-- A fresh process has a current session after smart auto-load but no in-memory
-- previous session. :Sess last should use the persisted order in that case.
state.set_prev_session(nil)
vim.notify = function() end
require("sess.ui.command").setup()
vim.cmd("Sess last")
fixture.equal(b.id, api.state.current().id)
fixture.equal(c.id, api.state.prev().id)

-- Once a previous session exists, retain the original toggle behavior.
vim.cmd("Sess last")
fixture.equal(c.id, api.state.current().id)
fixture.equal(b.id, api.state.prev().id)
