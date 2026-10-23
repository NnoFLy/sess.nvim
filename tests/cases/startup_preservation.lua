-- Startup buffers are recoverable editor objects, not an outgoing session.
local function setup(mode)
    return string.format(
        [[
assert(require("sess").setup({
    store_path = vim.env.SESS_TEST_ROOT .. "/store", smart_auto_load = %q,
    auto_save = false, tabline = { enabled = false },
}))
]],
        mode
    )
end
local function observe(assertions)
    return [[
vim.api.nvim_create_autocmd("VimEnter", { callback = function()
    vim.defer_fn(function() check(function()
]] .. assertions .. [[
    end) end, 40)
end })
]]
end

fixture.startup(setup("none") .. observe([[
local root = vim.env.SESS_TEST_ROOT
local api = require("sess.api")
vim.fn.mkdir(root .. "/other", "p")
assert(api.session.create(root .. "/other", { id = "other" }))
vim.fn.writefile({ "other context" }, root .. "/other/saved.txt")
vim.cmd.edit(root .. "/other/saved.txt")
assert(api.session.save())
assert(api.session.create(root, { id = "startup" }))
vim.fn.writefile({ "restored context" }, root .. "/saved.txt")
vim.cmd.edit(root .. "/saved.txt")
assert(api.session.save())
]]))

local preparation = [[
local root = vim.env.SESS_TEST_ROOT
local original = {}
local function remember(buf, text)
    original[buf] = { text = text, hidden = vim.bo[buf].bufhidden }
    return buf
end
vim.o.hidden = true
vim.o.autowrite = true
vim.o.autowriteall = true
vim.fn.writefile({ "on disk" }, root .. "/unsaved.txt")
local named = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(named, root .. "/unsaved.txt")
vim.api.nvim_buf_set_lines(named, 0, -1, false, { "unsaved named" })
vim.bo[named].bufhidden = "wipe"
remember(named, "unsaved named")
local unnamed = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(unnamed, 0, -1, false, { "unsaved unnamed" })
vim.bo[unnamed].bufhidden = "wipe"
remember(unnamed, "unsaved unnamed")
remember(vim.api.nvim_create_buf(false, true), "")
vim.cmd("split")
local plugin = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, plugin)
vim.bo[plugin].bufhidden = "wipe"
vim.api.nvim_buf_set_lines(plugin, 0, -1, false, { "plugin UI" })
remember(plugin, "plugin UI")
vim.cmd("new")
local terminal = vim.api.nvim_get_current_buf()
local job = vim.fn.jobstart({ "sh", "-c", "printf ready; sleep 60" }, { term = true })
assert(job > 0)
remember(terminal)
local floating = vim.api.nvim_create_buf(false, true)
vim.bo[floating].bufhidden = "wipe"
remember(floating, "")
vim.api.nvim_open_win(floating, true, {
    relative = "editor", row = 1, col = 1, width = 12, height = 3,
})
vim.cmd("tabnew")
-- The hide adapter drains callbacks after tab teardown. A new wipe-on-hide
-- plugin buffer created during that drain must survive the remaining teardown.
vim.api.nvim_create_autocmd("TabClosed", { once = true, callback = function()
    vim.schedule(function()
        vim.cmd("split")
        local callback_buffer = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_win_set_buf(0, callback_buffer)
        vim.bo[callback_buffer].bufhidden = "wipe"
        vim.api.nvim_buf_set_lines(callback_buffer, 0, -1, false, { "callback UI" })
        remember(callback_buffer, "callback UI")
    end)
end })
vim.o.hidden = false
]]

local preserved = [[
for buf, saved in pairs(original) do
    assert(vim.api.nvim_buf_is_valid(buf), "startup buffer deleted: " .. buf)
    assert(vim.api.nvim_buf_is_loaded(buf), "startup buffer unloaded: " .. buf)
    assert(vim.bo[buf].bufhidden == saved.hidden)
    if saved.text then
        assert(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == saved.text)
    end
end
assert(vim.bo[named].modified and vim.bo[unnamed].modified)
assert(vim.fn.jobwait({ job }, 0)[1] == -1)
assert(vim.fn.readfile(root .. "/unsaved.txt")[1] == "on disk")
assert(not vim.o.hidden and vim.o.autowrite and vim.o.autowriteall)
]]

local function startup(mode, assertions, before, success)
    vim.fn.writefile(
        { '{"version":1,"active_ids":["startup","other"],"current_id":"startup"}' },
        fixture.root .. "/store/resume.json"
    )
    local completion = success
            and [[
vim.api.nvim_create_autocmd("User", { pattern = "SessLoaded", callback = function(event)
    if event.data.current.id == "startup" then vim.schedule(function() check(function()
]] .. assertions .. [[
    end) end) end
end })
]]
        or observe(assertions)
    return fixture.startup(preparation .. setup(mode) .. (before or "") .. completion)
end

for _, mode in ipairs({ "current", "all" }) do
    startup(mode, preserved .. [[
local api = require("sess.api")
assert(api.state.current().id == "startup")
assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "restored context")
for buf in pairs(original) do
    assert(not vim.bo[buf].buflisted and #vim.fn.win_findbuf(buf) == 0)
end
assert(api.session.save())
for _, view in pairs(require("sess.state").get_views()) do
    for buf in pairs(original) do assert(not view.buffers[buf], "adopted startup buffer") end
end
local snapshot = table.concat(vim.fn.readfile(root .. "/store/sessions/startup/session.vim"), "\n")
assert(not snapshot:find("unsaved.txt", 1, true))
assert(api.session.unload()) -- no confirmation needed for unrelated modified buffers/jobs
]] .. preserved .. [[
-- Recovery is explicit; no extra session/context was created to hold these.
vim.cmd.buffer(named)
assert(vim.api.nvim_get_current_buf() == named)
assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "unsaved named")
]], nil, true)
end

-- With no match, current mode must not create a session from plugin/work state.
startup("current", preserved .. [[
assert(require("sess.api").state.current() == nil)
assert(#select(3, require("sess.api").session.list()) == 2)
assert(vim.bo[named].buflisted)
]], [[vim.fn.mkdir(root .. "/unmatched", "p"); vim.cmd.cd(root .. "/unmatched")]], false)

-- Missing/corrupt history leaves both layout and listing untouched.
for _, history in ipairs({ "", "broken" }) do
    startup(
        "all",
        preserved
            .. [[
assert(require("sess.api").state.current() == nil)
assert(vim.bo[named].buflisted)
assert(#vim.api.nvim_list_tabpages() == 2)
assert(transient_calls == 0, "no-op startup recreated plugin UI")
]],
        [[
local transient_calls = 0
assert(require("sess.editor").register_transient_owner({
    suspend = function() transient_calls = transient_calls + 1 end,
    resume = function() transient_calls = transient_calls + 1 end,
}))
]]
            .. (
                history == "" and [[vim.fn.delete(root .. "/store/resume.json")]]
                or [[vim.fn.writefile({ "broken" }, root .. "/store/resume.json")]]
            ),
        false
    )
end

-- Source failure rolls back the original live editor, not merely an empty view.
vim.fn.writefile(
    { "throw 'startup source failure'" },
    fixture.root .. "/store/sessions/startup/session.vim",
    "a"
)
local failed = startup("current", preserved .. [[
assert(require("sess.api").state.current() == nil)
assert(vim.bo[named].buflisted)
assert(#vim.api.nvim_list_tabpages() == 2)
]], nil, false)
assert(failed.stderr:find("startup source failure", 1, true))
