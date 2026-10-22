-- Two genuine managed instances, coordinated so the earlier-started instance
-- exits last. Readers must observe whole selections, never merged memberships.
local root = fixture.root
fixture.startup([[
local root = vim.env.SESS_TEST_ROOT
assert(require("sess").setup({ store_path = root .. "/store", smart_auto_load = "none", auto_save = false }))
vim.api.nvim_create_autocmd("VimEnter", { callback = function() vim.schedule(function() check(function()
local api = require("sess.api")
for _, id in ipairs({ "a", "b" }) do
    vim.fn.mkdir(root .. "/" .. id, "p")
    assert(api.session.create(root .. "/" .. id, { id = id }))
end
end) end) end })
]])
local path = root .. "/store/resume.json"
local function spawn(id)
    local config = root .. "/concurrent-" .. id .. ".lua"
    vim.fn.writefile(
        vim.split(
            string.format(
                [[
vim.opt.runtimepath:prepend(vim.env.SESS_TEST_REPO)
vim.opt.shadafile = "NONE"
vim.opt.swapfile = false
vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize" }
local root = vim.env.SESS_TEST_ROOT
local id = %q
assert(require("sess").setup({ store_path = root .. "/store", smart_auto_load = "none", auto_save = false }))
vim.api.nvim_create_autocmd("VimEnter", { callback = function() vim.schedule(function()
    local ok, err = require("sess.api").session.load(id)
    if not ok then io.stderr:write(err); vim.cmd("cquit 1"); return end
    vim.fn.writefile({ "ready" }, root .. "/ready-" .. id)
    local function exit_when_released()
        if vim.fn.filereadable(root .. "/exit-" .. id) == 1 then
            vim.cmd("qa!")
        else
            vim.defer_fn(exit_when_released, 5)
        end
    end
    exit_when_released()
end) end })
]],
                id
            ),
            "\n",
            { plain = true }
        ),
        config
    )
    return vim.system(
        { vim.v.progpath, "--headless", "-u", config, "-i", "NONE", "--noplugin", "-n" },
        { text = true }
    )
end
local a = spawn("a")
assert(vim.wait(5000, function()
    return vim.fn.filereadable(root .. "/ready-a") == 1
end))
local b = spawn("b")
assert(vim.wait(5000, function()
    return vim.fn.filereadable(root .. "/ready-b") == 1
end))
local allowed = { '["a","b"]', '["a"]', '["b"]' }
local function read_complete()
    local record = vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    assert(record.version == 1)
    assert(vim.tbl_contains(allowed, vim.json.encode(record.active_ids)))
    assert(vim.tbl_contains(record.active_ids, record.current_id))
    return record
end
for _, id in ipairs({ "b", "a" }) do
    local job = id == "b" and b or a
    vim.fn.writefile({ "exit" }, root .. "/exit-" .. id)
    for _ = 1, 100 do
        read_complete()
    end
    local result = job:wait(5000)
    assert(result.code == 0, result.stderr)
    fixture.equal({ id }, read_complete().active_ids)
end
fixture.equal("a", read_complete().current_id)
