-- Existing policy tests enumerate eligibility shapes. These use real snapshots
-- to prove that disqualified startups keep their editor context and history.
local setup = [[
local root = vim.env.SESS_TEST_ROOT
assert(require("sess").setup({ store_path = root .. "/store", smart_auto_load = "none", auto_save = false,
    tabline = { enabled = false } }))
local api = require("sess.api")
]]
local function after(assertions)
    return [[
vim.api.nvim_create_autocmd("VimEnter", { callback = function() vim.defer_fn(function() check(function()
]] .. assertions .. [[
end) end, 50) end })
]]
end
local function loaded(assertions)
    return [[
vim.api.nvim_create_autocmd("User", { pattern = "SessLoaded", once = true,
    callback = function() vim.schedule(function() check(function()
assert(api.state.current().id == "a")
assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "restored context")
]] .. (assertions or "") .. [[
    end) end) end,
})
]]
end
fixture.startup(setup .. after([[
assert(api.session.create(root, { id = "a" }))
vim.fn.writefile({ "restored context" }, root .. "/saved.txt")
vim.cmd.edit(root .. "/saved.txt")
assert(api.session.save())
]]))
vim.fn.writefile({ "explicit content" }, fixture.root .. "/explicit.txt")
vim.fn.writefile({ "let g:script = 1" }, fixture.root .. "/explicit.vim")
local path = fixture.root .. "/store/resume.json"
local history = vim.fn.readfile(path)
for _, mode in ipairs({ "current", "all" }) do
    local config = setup:gsub('smart_auto_load = "none"', 'smart_auto_load = "' .. mode .. '"')
    for _, case in ipairs({
        {
            { "explicit.txt" },
            'assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "explicit content")',
        },
        { { "--", "explicit.txt" }, 'assert(vim.api.nvim_buf_get_name(0):match("explicit.txt$"))' },
        { { "-c", "let g:explicit = 1" }, "assert(vim.g.explicit == 1)" },
        { { "+let g:explicit = 1" }, "assert(vim.g.explicit == 1)" },
        { { "--cmd", "let g:explicit = 1" }, "assert(vim.g.explicit == 1)" },
        { { "-S", "explicit.vim" }, "assert(vim.g.script == 1)" },
        {
            { "-" },
            'assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "stdin content")',
            "stdin content\n",
        },
    }) do
        fixture.startup(config .. after(case[2] .. [[
assert(api.state.current() == nil)
assert(#api.state.active() == 0)
]]), case[1], case[3])
        fixture.equal(history, vim.fn.readfile(path))
    end
    -- Option operands and a terminal separator still permit real restoration.
    fixture.startup(config .. loaded(), { "--startuptime", "+timing", "--" })
    history = vim.fn.readfile(path)
    -- A scheduled plugin edit is not typed input, and remains recoverable.
    fixture.startup([[
local displaced
vim.api.nvim_create_autocmd("VimEnter", { callback = function() vim.schedule(function()
displaced = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(displaced, 0, -1, false, { "late work" })
end) end })
]] .. config .. loaded([[
assert(vim.api.nvim_buf_get_lines(displaced, 0, -1, false)[1] == "late work")
assert(not vim.bo[displaced].buflisted)
]]))
    fixture.equal(
        vim.json.decode(table.concat(history, "\n")),
        vim.json.decode(table.concat(vim.fn.readfile(path), "\n"))
    )
    -- Plugin layout/cwd initialization permits a valid, usable snapshot.
    fixture.startup(config .. [[
vim.api.nvim_create_autocmd("VimEnter", { callback = function()
vim.cmd("split")
vim.bo.buftype = "nofile"
vim.cmd.lcd(root)
end })
]] .. loaded([[
assert(#vim.api.nvim_list_wins() == 1)
assert(vim.bo.buftype == "")
]]))
    history = vim.fn.readfile(path)
end
