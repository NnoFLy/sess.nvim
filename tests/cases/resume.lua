-- Primary seam: genuine configured startup -> normal exit -> fresh startup.
local setup = [[
local root = vim.env.SESS_TEST_ROOT
assert(require("sess").setup({
    store_path = root .. "/store", smart_auto_load = "none", auto_save = true,
    tabline = { enabled = false },
}))
local api = require("sess.api")
]]
fixture.startup(setup .. [[
vim.api.nvim_create_autocmd("VimEnter", { callback = function() vim.schedule(function()
    check(function()
        for _, name in ipairs({ "c", "a", "b" }) do
            local path = root .. "/" .. name
            vim.fn.mkdir(path, "p")
            vim.fn.writefile({ "contents " .. name }, path .. "/file.txt")
            local ok, err = api.session.create(path, { id = name, name = name })
            assert(ok, err)
            vim.cmd.edit(path .. "/file.txt")
            if name == "c" then
                assert(api.session.save())
                assert(api.session.unload())
            end
        end
    end)
end) end })
]])
fixture.startup(setup:gsub('smart_auto_load = "none"', 'smart_auto_load = "all"') .. [[
vim.api.nvim_create_autocmd("VimEnter", { callback = function() vim.defer_fn(function()
    check(function()
        assert(vim.deep_equal({ "a", "b" }, vim.tbl_map(function(s) return s.id end, api.state.active())))
        assert(api.state.current().id == "b")
        assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "contents b")
        assert(api.session.load("a"))
        assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "contents a")
    end)
end, 30) end })
]])
