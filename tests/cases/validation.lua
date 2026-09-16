fixture.setup()

local api = require("sess.api")
local storage = require("sess.storage")

local ok, err, item = api.session.create(fixture.directory("project"))
assert(ok, err)

local cwd, snapshot = vim.fn.getcwd(), assert(storage.read_session(item.id))
local function rejected(call)
    local success, message = call()
    assert(success == false or success == nil, "invalid input accepted")
    assert(type(message) == "string", "missing error")
    fixture.equal(cwd, vim.fn.getcwd())
    fixture.equal(item, api.state.current())
    fixture.equal(snapshot, storage.read_session(item.id))
end

for _, id in ipairs({ "../escape", "a/b", "", "/tmp/escape", {}, false }) do
    for _, name in ipairs({
        "create",
        "replace_snapshot",
        "delete",
        "read_metadata",
        "write_metadata",
        "create_with_metadata",
        "get_session_path",
        "read_session",
        "write_session",
    }) do
        rejected(function()
            return storage[name](id, {})
        end)
    end

    rejected(function()
        return storage.rename(item.id, id)
    end)

    rejected(function()
        return storage.rename(id, "valid")
    end)
end

for _, target in ipairs({ 1, false, {}, { id = {} }, { id = "../escape", metadata = {} }, "" }) do
    for _, name in ipairs({ "load", "save", "delete", "toggle_pin", "resolve" }) do
        rejected(function()
            return api.session[name](target)
        end)
    end
end

for _, opts in ipairs({
    false,
    1,
    { before_load = false },
    { after_load = { custom = 1 } },
    { on_unload = { custom = false } },
    { before_load = { auto_save_files = "yes" } },
}) do
    rejected(function()
        return api.session.load(item, opts)
    end)

    rejected(function()
        return api.session.delete(item, opts)
    end)

    rejected(function()
        return api.session.unload(opts)
    end)
end

rejected(function()
    return api.session.create(1)
end)

rejected(function()
    return api.session.create(fixture.directory("new"), { id = "../escape" })
end)

rejected(function()
    return api.session.create(fixture.directory("new"), { name = "" })
end)

rejected(function()
    return api.session.create(fixture.directory("new"), { id = item.id })
end)

fixture.equal(nil, api.state.replace)
fixture.equal(nil, api.state.set_current)
