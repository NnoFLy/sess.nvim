fixture.setup()

local api = require("sess.api")

local ok, err, a = api.session.create(fixture.directory("a"))
assert(ok, err)
vim.o.hidden = true

local named = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(named, a.metadata.cwd .. "/unsaved.txt")
vim.api.nvim_buf_set_lines(named, 0, -1, false, { "unsaved named" })

local unnamed = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(unnamed, 0, -1, false, { "unsaved unnamed" })

local scratch = vim.api.nvim_create_buf(true, true)
vim.api.nvim_win_set_buf(0, scratch)
vim.bo[scratch].bufhidden = "wipe"
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "scratch work" })
vim.cmd("split")
vim.cmd("enew")

local terminal = vim.api.nvim_get_current_buf()
local job = vim.fn.jobstart({ "sh", "-c", "printf ready; sleep 60" }, { term = true })
assert(job > 0)

local floating = vim.api.nvim_create_buf(false, true)
vim.bo[floating].bufhidden = "wipe"
vim.api.nvim_open_win(
    floating,
    false,
    { relative = "editor", row = 1, col = 1, width = 12, height = 3 }
)
vim.o.hidden = false
vim.o.autowrite = true
vim.o.autowriteall = true

local buffers = { named, unnamed, scratch, terminal }
local b
ok, err, b = api.session.create(fixture.directory("b"))
assert(ok, err)

for _, buf in ipairs(buffers) do
    assert(vim.api.nvim_buf_is_loaded(buf), "buffer was unloaded: " .. buf)
    assert(not vim.bo[buf].buflisted, "outgoing buffer is listed: " .. buf)
    assert(#vim.fn.win_findbuf(buf) == 0, "outgoing buffer is visible")
end

assert(vim.api.nvim_buf_is_loaded(floating))
fixture.equal(0, #vim.fn.win_findbuf(floating))
fixture.equal(-1, vim.fn.jobwait({ job }, 0)[1])
fixture.equal(false, vim.o.hidden)
fixture.equal(true, vim.o.autowrite)
fixture.equal(true, vim.o.autowriteall)
fixture.equal(0, vim.fn.filereadable(a.metadata.cwd .. "/unsaved.txt"))
assert(api.session.load(a))

for _, buf in ipairs(buffers) do
    assert(vim.bo[buf].buflisted)
end

fixture.equal(1, #vim.fn.win_findbuf(floating))
fixture.equal(terminal, vim.api.nvim_get_current_buf())
fixture.equal(-1, vim.fn.jobwait({ job }, 0)[1])
fixture.equal({ "unsaved named" }, vim.api.nvim_buf_get_lines(named, 0, -1, false))
fixture.equal({ "unsaved unnamed" }, vim.api.nvim_buf_get_lines(unnamed, 0, -1, false))
assert(vim.bo[named].modified and vim.bo[unnamed].modified)
assert(api.session.load(b))
assert(api.session.load(a))
fixture.equal(terminal, vim.api.nvim_get_current_buf())
assert(api.session.unload(nil, {
    confirm = function(request)
        return request.kind == "buffers" and "discard" or "stop"
    end,
}))
for _, buf in ipairs(buffers) do
    assert(not vim.api.nvim_buf_is_valid(buf), "buffer survived unload: " .. buf)
end
assert(not vim.api.nvim_buf_is_valid(floating))
assert(vim.fn.jobwait({ job }, 3000)[1] ~= -1)
fixture.equal(nil, require("sess.state").get_view(a.id))
fixture.equal(false, vim.o.hidden)
fixture.equal(true, vim.o.autowrite)
fixture.equal(true, vim.o.autowriteall)
