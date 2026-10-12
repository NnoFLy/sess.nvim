fixture.setup()

local api = require("sess.api")
local storage = require("sess.storage")

local ok, err, item = api.session.create(fixture.directory("project"), { name = "project" })
assert(ok, err)
local catalog_path = fixture.root .. "/store/catalog.json"
assert(vim.fn.filereadable(catalog_path) == 1)

-- Normal catalog reads do not fall back to one metadata file per session.
local read_metadata = storage.read_metadata
storage.read_metadata = function()
    error("metadata fallback should not be used")
end
local listed_ok, listed_err, listed = api.session.list()
storage.read_metadata = read_metadata
assert(listed_ok, listed_err)
fixture.equal(item.id, listed[1].id)

local updated = vim.deepcopy(item.metadata)
updated.name = "updated"
assert(storage.write_metadata(item.id, updated))
local refreshed_ok, refreshed_err, refreshed = api.session.get(item.id)
assert(refreshed_ok, refreshed_err)
fixture.equal("updated", refreshed.metadata.name)

local marks = assert(storage.read_marks())
marks.a = item.id
assert(storage.write_marks(marks))
local cached = assert(storage.read_marks())
local fs_read = vim.uv.fs_read
vim.uv.fs_read = function()
    error("mark cache should avoid rereading the registry")
end
local cached_again, cached_err = storage.read_marks()
vim.uv.fs_read = fs_read
assert(cached_again, cached_err)
fixture.equal(cached, cached_again)
