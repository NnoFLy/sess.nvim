vim.opt.runtimepath:prepend(vim.env.SESS_TEST_REPO)
vim.opt.shadafile = "NONE"
vim.opt.swapfile = false
vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize" }

local root = vim.env.SESS_TEST_ROOT
vim.fn.chdir(root)
local process_id = 0
_G.fixture = {
    root = root,
    setup = function(store_name)
        assert(require("sess").setup({
            store_path = root .. "/" .. (store_name or "store"),
            smart_auto_load = "none",
            auto_save = false,
        }))
    end,
    -- Run a genuine startup, without the harness's disqualifying -c launcher.
    startup = function(code, args, stdin)
        process_id = process_id + 1
        local config = root .. "/startup-" .. process_id .. ".lua"
        local prelude = [[
vim.opt.runtimepath:prepend(vim.env.SESS_TEST_REPO)
vim.opt.shadafile = "NONE"
vim.opt.swapfile = false
vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize" }
_G.check = function(fn)
    local ok, err = xpcall(fn, debug.traceback)
    if not ok then
        io.stderr:write(err .. "\n")
        vim.cmd("cquit 1")
    else
        vim.cmd("qa!")
    end
end
]]
        vim.fn.writefile(vim.split(prelude .. code, "\n", { plain = true }), config)
        local command =
            { vim.v.progpath, "--headless", "-u", config, "-i", "NONE", "--noplugin", "-n" }
        vim.list_extend(command, args or {})
        local result = vim.system(command, { cwd = root, stdin = stdin, text = true }):wait(10000)
        assert(
            result.code == 0,
            "startup failed: " .. (result.stderr or "") .. (result.stdout or "")
        )
        return result
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
