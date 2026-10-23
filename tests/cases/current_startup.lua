local function start(store, before, assertions)
    return fixture.startup(string.format(
        [[
local root = vim.env.SESS_TEST_ROOT
%s
assert(require("sess").setup({ store_path = root .. "/%s", auto_save = false,
    tabline = { enabled = false } }))
local api = require("sess.api")
vim.api.nvim_create_autocmd("VimEnter", { callback = function() vim.defer_fn(function()
    check(function()
%s
    end)
end, 30) end })
]],
        before or "",
        store,
        assertions
    ))
end

-- Unmatched exact cwd creates; a child does not select a parent's session.
start(
    "store",
    "",
    [[
assert(api.state.current().metadata.cwd == root)
assert(#api.state.active() == 1)
]]
)
start(
    "store",
    [[vim.fn.mkdir(root .. "/child", "p"); vim.cmd.cd(root .. "/child")]],
    [[
assert(api.state.current().metadata.cwd == root .. "/child")
assert(#select(3, api.session.list()) == 2)
]]
)
-- Canonical path identity loads the saved root context, not a new session.
start(
    "store",
    [[
assert(vim.uv.fs_symlink(root, root .. "/alias"))
vim.cmd.cd(root .. "/alias/child/..")
]],
    [[
assert(api.state.current().metadata.cwd == root)
assert(#select(3, api.session.list()) == 2)
]]
)

-- No creation after a failed lookup.
local failed = start(
    "failed",
    [[
vim.fn.readdir = function() error("injected catalog failure") end
]],
    [[assert(api.state.current() == nil)]]
)
assert(failed.stderr:find("injected catalog failure", 1, true))

-- Prepare ambiguous metadata on disk, then let genuine startup resolve it.
fixture.startup([[
local root = vim.env.SESS_TEST_ROOT
assert(require("sess").setup({ store_path = root .. "/ambiguous", smart_auto_load = "none", auto_save = false }))
local api = require("sess.api")
vim.api.nvim_create_autocmd("VimEnter", { callback = function() vim.schedule(function() check(function()
assert(api.session.create(root, { id = "a" }))
vim.fn.mkdir(root .. "/other", "p")
assert(api.session.create(root .. "/other", { id = "b" }))
local storage = require("sess.storage")
local metadata = assert(storage.read_metadata("b"))
metadata.cwd = root
assert(storage.write_metadata("b", metadata))
end) end) end })
]])
local ambiguous = start(
    "ambiguous",
    "",
    [[
assert(api.state.current() == nil)
assert(#select(3, api.session.list()) == 2)
]]
)
assert(ambiguous.stderr:find("ambiguous", 1, true))

-- A matched session with a missing snapshot is an error, never a replacement.
local record =
    vim.json.decode(table.concat(vim.fn.readfile(fixture.root .. "/store/resume.json"), "\n"))
local id = record.current_id
assert(vim.uv.fs_unlink(fixture.root .. "/store/sessions/" .. id .. "/session.vim"))
local unavailable = start(
    "store",
    "",
    [[
assert(api.state.current() == nil)
assert(#select(3, api.session.list()) == 2)
]]
)
assert(unavailable.stderr:find("session.vim", 1, true), unavailable.stderr)
