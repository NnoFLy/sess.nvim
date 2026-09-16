local api = require("sess.api")

for name, operation in pairs(api.session) do
    local ok, err = operation()
    fixture.equal(false, ok)
    assert(type(err) == "string" and err:match("initializ"), name .. ": " .. tostring(err))
end

local items, err = api.items.get_items()
fixture.equal({}, items)
assert(err:match("initializ"))
