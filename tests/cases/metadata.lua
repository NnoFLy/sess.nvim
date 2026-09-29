fixture.setup()

local api = require("sess.api")
local storage = require("sess.storage")

local ok, err, item = api.session.create(fixture.directory("healthy"))
assert(ok, err)
assert(storage.create("json"))
vim.fn.writefile({ "not json" }, fixture.root .. "/store/sessions/json/metadata.json")
assert(storage.create("version"))
assert(storage.create("relative"))
assert(storage.create("nul"))

local metadata = vim.deepcopy(item.metadata)
metadata.version = -1
local rejected, reject_err = storage.write_metadata("version", metadata)
assert(not rejected)
assert(reject_err:match("unsupported session metadata version"), reject_err)
assert(metadata.version == -1, "write_metadata must not mutate its input")

local without_version = vim.deepcopy(item.metadata)
without_version.version = nil
assert(storage.write_metadata(item.id, without_version))
assert(without_version.version == nil, "write_metadata must not add defaults to its input")

vim.fn.writefile(
    { vim.json.encode(metadata) },
    fixture.root .. "/store/sessions/version/metadata.json"
)

local relative = vim.deepcopy(item.metadata)
relative.cwd = "relative/project"
local relative_ok, relative_err = storage.write_metadata("relative", relative)
assert(not relative_ok)
assert(relative_err:match("absolute canonical path"), relative_err)

local function write_raw_metadata(id, value)
    local file = assert(io.open(fixture.root .. "/store/sessions/" .. id .. "/metadata.json", "wb"))
    assert(file:write(vim.json.encode(value)))
    assert(file:close())
end

local nul = vim.deepcopy(item.metadata)
nul.cwd = item.metadata.cwd .. "\0invalid"
write_raw_metadata("nul", nul)

local success, list_err, sessions, diagnostics = api.session.list()
assert(success, list_err)
fixture.equal(1, #sessions)
fixture.equal(4, #diagnostics)
local diagnostic_text = table.concat(diagnostics, "\\n")
assert(diagnostic_text:match("invalid JSON"))
assert(diagnostic_text:match("unsupported session metadata version"))
assert(diagnostic_text:match("relative"))
assert(diagnostic_text:match("nul"))

local loaded, load_err = api.session.load("json")
assert(not loaded and load_err:match("invalid JSON"))
fixture.equal(item.id, api.state.current().id)
local found, lookup_err, found_item, lookup_diagnostics = api.session.get_by_name(item.metadata.name)
assert(found, lookup_err)
fixture.equal(item.id, found_item.id)
fixture.equal(diagnostics, lookup_diagnostics)
fixture.equal({ "not json" }, vim.fn.readfile(fixture.root .. "/store/sessions/json/metadata.json"))
