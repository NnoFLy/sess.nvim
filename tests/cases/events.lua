fixture.setup()

local api = require("sess.api")

local observed = {}
vim.notify = function()
    error("core must not notify")
end

vim.fn.confirm = function()
    error("core must not prompt")
end

vim.api.nvim_create_autocmd("User", {
    pattern = {
        "SessCreated",
        "SessLoaded",
        "SessSaved",
        "SessUnloaded",
        "SessDeleted",
        "SessRenamed",
        "SessPinned",
    },
    callback = function(event)
        table.insert(observed, event.match)
        assert(event.data.session.id)
        fixture.equal(api.state.current(), event.data.current)
    end,
})

local ok, err, a, diagnostics = api.session.create(fixture.directory("a"), {
    hooks = {
        after_operation = function(payload)
            fixture.equal("create", payload.operation)
            assert(api.state.current())
            table.insert(observed, "hook")
            error("post hook failed")
        end,
    },
})

assert(ok, err)
assert(diagnostics[1]:match("post hook failed"))
fixture.equal({ "hook", "SessCreated" }, observed)

local _, _, b = api.session.create(fixture.directory("b"))
local count = #observed
assert(api.session.delete(a))
fixture.equal(count + 1, #observed)
fixture.equal("SessDeleted", observed[#observed])

-- An event subscriber failure remains a successful operation and diagnostic.
vim.api.nvim_create_autocmd("User", {
    pattern = "SessLoaded",
    callback = function()
        error("subscriber failure")
    end,
})

ok, err, _, diagnostics = api.session.unload({
    hooks = {
        after_operation = function()
            error("unload hook")
        end,
    },
})

assert(ok, err)
assert(#diagnostics >= 1)

-- Silence only the intentional native autocmd error in this test. The API
-- must still return the subscriber diagnostic and committed success.
_G.sess_test_failing_subscriber = function()
    ok, err, _, diagnostics = api.session.load(b)
end

vim.cmd("silent! lua sess_test_failing_subscriber()")
_G.sess_test_failing_subscriber = nil
assert(ok, err)
assert(table.concat(diagnostics, " "):match("subscriber failure"))
fixture.equal(b.id, api.state.current().id)
ok, err, _, diagnostics = api.session.delete(b, {
    hooks = {
        after_operation = function()
            error("delete hook")
        end,
    },
})

assert(ok, err)
fixture.equal(nil, api.state.current())
fixture.equal(2, #diagnostics)
fixture.equal("SessUnloaded", observed[#observed - 1])
fixture.equal("SessDeleted", observed[#observed])
assert(not api.session.save("anything"))
fixture.equal(nil, api.session.prepare)
fixture.equal(nil, api.session.commit)
