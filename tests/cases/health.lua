local messages = {}

for _, level in ipairs({ "start", "ok", "warn", "error", "info" }) do
    vim.health[level] = function(message)
        table.insert(messages, level .. ": " .. message)
    end
end

require("sess.health").check()
assert(table.concat(messages, "\n"):match("not initialized"))
fixture.setup()

local api = require("sess.api")
local storage = require("sess.storage")

local _, _, item = api.session.create(fixture.directory("healthy"))
assert(storage.write_session(item.id, "let g:health_sourced_snapshot = 1"))
assert(storage.create("broken"))
messages = {}
require("sess.health").check()
assert(table.concat(messages, "\n"):match("broken"))
fixture.equal(nil, vim.g.health_sourced_snapshot)
fixture.equal("let g:health_sourced_snapshot = 1", storage.read_session(item.id))
vim.uv.fs_unlink(assert(storage.get_session_path(item.id)))
messages = {}
require("sess.health").check()
assert(table.concat(messages, "\n"):match("Missing/unreadable snapshot"))
assert(storage.exists("broken"))
