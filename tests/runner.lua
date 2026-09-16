vim.opt.runtimepath:prepend(vim.env.SESS_TEST_REPO)
vim.opt.shadafile = "NONE"
vim.opt.swapfile = false
vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize" }

local root = vim.env.SESS_TEST_ROOT
vim.fn.chdir(root)
_G.fixture = {
    root = root,
    setup = function(store_name)
        assert(require("sess").setup({
            store_path = root .. "/" .. (store_name or "store"),
            smart_auto_load = false,
            auto_save = false,
        }))
    end,
    directory = function(name)
        local path = root .. "/" .. name
        vim.fn.mkdir(path, "p")

        return path
    end,
    equal = function(expected, actual)
        assert(
            vim.deep_equal(expected, actual),
            "expected " .. vim.inspect(expected) .. ", got " .. vim.inspect(actual)
        )
    end,
}

local ok, err = xpcall(function()
    dofile(vim.env.SESS_TEST_CASE)
end, debug.traceback)
if not ok then
    io.stderr:write(err .. "\n")
    vim.cmd("cquit 1")
else
    vim.cmd("qa!")
end
