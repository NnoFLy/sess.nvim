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

-- Exact ID lookups must not rescan the whole catalog.
local list_metadata = storage.list_metadata
storage.list_metadata = function()
    error("exact ID lookup should not list the catalog")
end
local direct_ok, direct_err, direct_item = api.session.get(item.id)
storage.list_metadata = list_metadata
assert(direct_ok, direct_err)
fixture.equal(item.id, direct_item.id)

-- Resolve all marks against one catalog snapshot instead of one scan per mark.
local list_calls = 0
storage.list_metadata = function(...)
    list_calls = list_calls + 1
    return list_metadata(...)
end
local marks_ok, marks_err = api.session.list_marks()
storage.list_metadata = list_metadata
assert(marks_ok, marks_err)
fixture.equal(1, list_calls)

-- External writers must invalidate cached presence, contents, and errors.
local mark_path = fixture.root .. "/store/marks.json"
assert(vim.uv.fs_unlink(mark_path))
fixture.equal({}, assert(storage.read_marks()))
local function external_marks(value)
    vim.fn.writefile({ vim.json.encode({ version = 1, marks = value }) }, mark_path)
end
external_marks({ b = item.id })
fixture.equal({ b = item.id }, assert(storage.read_marks()))
external_marks({ c = item.id })
fixture.equal({ c = item.id }, assert(storage.read_marks()))
vim.fn.writefile({ "not JSON" }, mark_path)
local invalid_marks, invalid_err = storage.read_marks()
assert(not invalid_marks and invalid_err:match("invalid JSON"), tostring(invalid_err))
external_marks({ a = item.id })
fixture.equal({ a = item.id }, assert(storage.read_marks()))

-- Replacement can commit before descriptor cleanup reports failure.
local rename, close = vim.uv.fs_rename, vim.uv.fs_close
local committed_parent
vim.uv.fs_rename = function(source, destination)
    local renamed, rename_err = rename(source, destination)
    if renamed and destination:match("/marks%.json$") then
        committed_parent = tonumber(destination:match("/fd/(%d+)/marks%.json$"))
    end
    return renamed, rename_err
end
vim.uv.fs_close = function(fd)
    if fd == committed_parent then
        return nil, "injected post-rename close failure"
    end
    return close(fd)
end
local written, write_err = storage.write_marks({ d = item.id })
vim.uv.fs_rename, vim.uv.fs_close = rename, close
if committed_parent then
    assert(not written and write_err:match("post%-rename close failure"), tostring(write_err))
else
    assert(written, write_err)
end
fixture.equal({ d = item.id }, assert(storage.read_marks()))

-- Invalid IDs and corrupt records retain diagnostics without rebuilding on
-- every picker invocation. Only a changed record should force another read.
vim.fn.mkdir(fixture.root .. "/store/sessions/bad!", "p")
assert(storage.create("corrupt"))
vim.fn.writefile({ "broken" }, fixture.root .. "/store/sessions/corrupt/metadata.json")
local first_list_ok, first_list_err, _, first_diagnostics = api.session.list()
assert(first_list_ok, first_list_err)
fixture.equal(2, #first_diagnostics)
vim.uv.fs_read = function()
    error("unchanged damaged store should not rebuild the catalog")
end
local second_list_ok, second_list_err, _, second_diagnostics = api.session.list()
vim.uv.fs_read = fs_read
assert(second_list_ok, second_list_err)
fixture.equal(first_diagnostics, second_diagnostics)
assert(storage.delete("corrupt", true))
assert(vim.fn.delete(fixture.root .. "/store/sessions/bad!", "d") == 0)
assert(api.session.list())

-- A same-length atomic replacement with preserved mtime is still a change.
local metadata_path = fixture.root .. "/store/sessions/" .. item.id .. "/metadata.json"
local previous_stat = assert(vim.uv.fs_lstat(metadata_path))
local replacement = metadata_path .. ".replacement"
local file = assert(io.open(replacement, "wb"))
assert(file:write(string.rep("x", previous_stat.size)))
assert(file:close())
assert(vim.uv.fs_utime(
    replacement,
    previous_stat.atime.sec + previous_stat.atime.nsec / 1e9,
    previous_stat.mtime.sec + previous_stat.mtime.nsec / 1e9
))
assert(vim.uv.fs_rename(replacement, metadata_path))
local changed_ok, changed_err, changed_sessions, changed_diagnostics = api.session.list()
assert(changed_ok, changed_err)
fixture.equal({}, changed_sessions)
assert(table.concat(changed_diagnostics, "; "):match("invalid JSON"))
