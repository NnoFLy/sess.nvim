fixture.setup()

local api = require("sess.api")
local editor = require("sess.editor")
vim.o.hidden = true

local _, _, a = api.session.create(fixture.directory("a"))
local shared = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(shared, a.metadata.cwd .. "/shared.txt")
vim.api.nvim_buf_set_lines(shared, 0, -1, false, { "shared unsaved text" })
local exclusive = vim.api.nvim_create_buf(true, false)
vim.cmd("enew")
local terminal = vim.api.nvim_get_current_buf()
local job = vim.fn.jobstart({ "sh", "-c", "sleep 60" }, { term = true })

local _, _, b = api.session.create(fixture.directory("b"))
vim.api.nvim_win_set_buf(0, terminal)
vim.bo[terminal].buflisted = true
vim.bo[shared].buflisted = true
local view = editor.capture()

-- Non-current unload retains any buffer/job also used by the current editor.
assert(api.session.unload(a, {
    confirm = function()
        error("shared resources must not need confirmation")
    end,
}))
assert(not vim.api.nvim_buf_is_valid(exclusive))
view.listing[exclusive] = nil
fixture.equal(view, editor.capture())
fixture.equal(b.id, api.state.current().id)
assert(vim.api.nvim_buf_is_valid(shared) and vim.bo[shared].modified)
fixture.equal(-1, vim.fn.jobwait({ job }, 0)[1])
fixture.equal(nil, require("sess.state").get_view(a.id))

-- Current unload also respects ownership by another hidden session.
local _, _, c = api.session.create(fixture.directory("c"))
vim.api.nvim_win_set_buf(0, terminal)
vim.bo[terminal].buflisted = true
vim.bo[shared].buflisted = true
assert(api.session.unload(c, {
    confirm = function()
        error("shared resources must not need confirmation")
    end,
}))
fixture.equal(nil, api.state.current())
assert(vim.api.nvim_buf_is_valid(shared) and vim.bo[shared].modified)
fixture.equal(-1, vim.fn.jobwait({ job }, 0)[1])

-- Only the last owning session's unload closes the shared resources.
local confirmations = {}
assert(api.session.unload(b, {
    confirm = function(request)
        table.insert(confirmations, request.kind)
        return request.kind == "buffers" and "discard" or "stop"
    end,
}))
fixture.equal({ "buffers", "jobs" }, confirmations)
assert(not vim.api.nvim_buf_is_valid(shared))
assert(not vim.api.nvim_buf_is_valid(terminal))
assert(vim.fn.jobwait({ job }, 3000)[1] ~= -1)
