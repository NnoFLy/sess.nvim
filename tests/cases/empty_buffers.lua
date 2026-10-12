fixture.setup()

local api = require("sess.api")

local function listed_unnamed()
    local count = 0
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_get_name(buf) == "" and vim.bo[buf].buflisted then
            count = count + 1
        end
    end
    return count
end

local ok, err, first = api.session.create(fixture.directory("first"))
assert(ok, err)
fixture.equal(1, listed_unnamed())
local first_buffer = vim.api.nvim_get_current_buf()

-- A clean transition placeholder can be shared instead of creating another
-- unnamed buffer for every new session.
ok, err = api.session.create(fixture.directory("second"))
assert(ok, err)
fixture.equal(first_buffer, vim.api.nvim_get_current_buf())
fixture.equal(1, listed_unnamed())

-- Modified unnamed buffers are never reused or discarded.
vim.api.nvim_buf_set_lines(first_buffer, 0, -1, false, { "keep this edit" })
ok, err = api.session.create(fixture.directory("third"))
assert(ok, err)
fixture.equal(1, listed_unnamed())
assert(vim.api.nvim_get_current_buf() ~= first_buffer)
assert(vim.api.nvim_buf_is_valid(first_buffer))
fixture.equal({ "keep this edit" }, vim.api.nvim_buf_get_lines(first_buffer, 0, -1, false))

assert(api.session.load(first))
fixture.equal(1, listed_unnamed())
fixture.equal(first_buffer, vim.api.nvim_get_current_buf())
