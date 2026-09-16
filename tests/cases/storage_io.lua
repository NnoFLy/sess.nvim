fixture.setup()

local storage = require("sess.storage")
local api = require("sess.api")

local ok, err, item = api.session.create(fixture.directory("project"))
assert(ok, err)

local directory = fixture.root .. "/store/sessions/" .. item.id
local metadata_path = directory .. "/metadata.json"
local original = vim.fn.readfile(metadata_path)
local updated = vim.deepcopy(item.metadata)
updated.name = "must not be committed"

-- A close failure must not publish the temporary metadata file, even when
-- write and flush succeeded. Always close the real handle in the test.
local open = io.open
io.open = function(path, mode)
    local file, open_err = open(path, mode)
    if not file or mode ~= "w" then
        return file, open_err
    end

    return {
        write = function(_, content)
            return file:write(content)
        end,
        flush = function()
            return file:flush()
        end,
        close = function()
            file:close()

            return nil, "injected close failure"
        end,
    }
end

ok, err = storage.write_metadata(item.id, updated)
io.open = open
assert(not ok and err:match("injected close failure"), tostring(err))
fixture.equal(original, vim.fn.readfile(metadata_path))

for _, name in ipairs(vim.fn.readdir(directory)) do
    assert(not name:match("%.tmp%-"), "leaked temporary file: " .. name)
end

-- Preserve the filesystem's read error instead of returning nil without one.
io.open = function(path, mode)
    if path == metadata_path and mode == "r" then
        return {
            read = function()
                return nil, "injected read failure"
            end,
            close = function()
                return true
            end,
        }
    end

    return open(path, mode)
end

local metadata
metadata, err = storage.read_metadata(item.id)
io.open = open
fixture.equal(nil, metadata)
fixture.equal("injected read failure", err)
assert(storage.write_metadata(item.id, updated))
fixture.equal(updated, storage.read_metadata(item.id))
