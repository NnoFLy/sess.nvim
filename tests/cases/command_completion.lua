fixture.setup()

local api = require("sess.api")
local _, _, spaced = api.session.create(fixture.directory("spaced"), { name = "space name" })
assert(spaced)
require("sess.ui.command").setup()

local session_matches = vim.fn.getcompletion("Sess rename ", "cmdline")
local found_session
for _, value in ipairs(session_matches) do
    if value == "space\\ name" then
        found_session = true
    end
end
assert(found_session, "session completion should escape spaces")
local mark_matches = vim.fn.getcompletion("Sess mark @a ", "cmdline")
local found_mark_target
for _, value in ipairs(mark_matches) do
    if value == "space\\ name" then
        found_mark_target = true
    end
end
assert(found_mark_target, "mark target completion should escape spaces")
assert(api.session.delete(spaced.id))
local deleted_matches = vim.fn.getcompletion("Sess restore ", "cmdline")
local found_deleted
for _, value in ipairs(deleted_matches) do
    if value == "space\\ name" then
        found_deleted = true
    end
end
assert(found_deleted, "deleted-session completion should escape spaces")
