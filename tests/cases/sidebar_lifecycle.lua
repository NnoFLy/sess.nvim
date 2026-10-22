fixture.setup()
local api = require("sess.api")
local editor = require("sess.editor")
local _, _, first = api.session.create(fixture.directory("first"), { name = "first" })
local first_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(first_buf, 0, -1, false, { "keep unsaved work" })
local _, _, second = api.session.create(fixture.directory("second"), { name = "second" })
local second_buf = vim.api.nvim_get_current_buf()
api.active.snapshot_async = function(done)
    done(api.active.snapshot())
end
local sidebar = require("sess.ui.sidebar")
sidebar.configure({ refresh_interval = 60000, width = 40 })
assert(sidebar.open())
local function select(name)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)
        if vim.api.nvim_buf_get_name(buf):match("Sess Sidebar$") then
            vim.api.nvim_set_current_win(win)
            for index, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
                if line:find(name, 1, true) then
                    vim.api.nvim_win_set_cursor(win, { index, 0 })
                    return win, buf
                end
            end
        end
    end
    error("missing sidebar target " .. name)
end
local function key(lhs)
    return vim.fn.maparg(lhs, "n", false, true).callback()
end
local function assert_transient_excluded()
    local view = editor.capture()
    for _, tab in ipairs(view.tabs) do
        for _, window in pairs(tab.windows) do
            assert(not editor.is_transient_buffer(window.buf))
        end
    end
    for buf in pairs(view.buffers) do
        assert(not editor.is_transient_buffer(buf))
    end
    local path = vim.fn.tempname()
    assert(editor.write_snapshot(path))
    assert(not table.concat(vim.fn.readfile(path), "\n"):find("Sess Sidebar", 1, true))
    vim.fn.delete(path)
end
select("first")
key("<CR>")
fixture.equal(first.id, api.state.current().id)
assert(sidebar.is_open())
assert(vim.api.nvim_buf_is_valid(first_buf) and vim.bo[first_buf].modified)
assert(vim.api.nvim_buf_is_valid(second_buf))
assert_transient_excluded()

-- Before-hook failure retains the live editor and sidebar.
local original_options = api.opts.get
api.opts.get = function()
    local options = original_options()
    options.hooks.before_transition = function()
        error("blocked switch")
    end
    return options
end
select("second")
key("<CR>")
fixture.equal(first.id, api.state.current().id)
assert(sidebar.is_open() and vim.api.nvim_buf_is_valid(first_buf))
api.opts.get = original_options

-- Shared safe unload gathers consent without losing the logical sidebar.
select("first")
vim.fn.confirm = function(message, choices, default)
    assert(message:find("first", 1, true))
    assert(choices:find("Save", 1, true) and default == 3)
    return 3
end
key("uu")
fixture.equal(first.id, api.state.current().id)
assert(vim.api.nvim_buf_is_valid(first_buf) and vim.bo[first_buf].modified)
assert(sidebar.is_open())
select("first")
vim.fn.confirm = function()
    return 2
end -- discard approved modified text
key("uu")
assert(api.state.current() == nil)
assert(not vim.api.nvim_buf_is_valid(first_buf))
assert(sidebar.is_open())
assert_transient_excluded()

-- Delete cancellation leaves live resources alone; committed current deletion
-- removes only storage/state, not modified buffers or running terminal jobs.
assert(api.session.load(second.id))
assert(sidebar.refresh())
vim.api.nvim_set_current_buf(second_buf)
vim.api.nvim_buf_set_lines(second_buf, 0, -1, false, { "delete preserves edits" })
vim.cmd("vsplit")
vim.cmd("enew")
local terminal = vim.api.nvim_get_current_buf()
local job = vim.fn.jobstart({ "sh", "-c", "sleep 60" }, { term = true })
-- Approving modified text is not consent to stop terminal jobs.
select("second")
local job_prompt = false
vim.fn.confirm = function(_, choices, default)
    if choices:find("Stop", 1, true) then
        job_prompt = true
        fixture.equal(2, default)
        return 2
    end
    return 2 -- discard, but all choices must complete before any teardown
end
key("uu")
assert(job_prompt)
fixture.equal(second.id, api.state.current().id)
assert(vim.api.nvim_buf_is_valid(second_buf) and vim.bo[second_buf].modified)
fixture.equal(-1, vim.fn.jobwait({ job }, 0)[1])
assert(sidebar.is_open())
select("second")
vim.fn.confirm = function()
    return 2
end
key("dd")
fixture.equal(second.id, api.state.current().id)
assert(sidebar.is_open())
select("second")
vim.fn.confirm = function(message, _, default)
    assert(message:find("second", 1, true) and default == 2)
    return 1
end
key("dd")
assert(api.state.current() == nil)
assert(sidebar.is_open())
assert(vim.api.nvim_buf_is_valid(second_buf) and vim.bo[second_buf].modified)
assert(vim.api.nvim_buf_is_valid(terminal))
fixture.equal(-1, vim.fn.jobwait({ job }, 0)[1])
assert_transient_excluded()
vim.fn.jobstop(job)
assert(sidebar.close())

-- A committed safe unload stops only the approved job and reattaches.
local _, _, third = api.session.create(fixture.directory("third"), { name = "third" })
local third_buf = vim.api.nvim_get_current_buf()
local third_job = vim.fn.jobstart({ "sh", "-c", "sleep 60" }, { term = true })
assert(sidebar.open())
select("third")
vim.fn.confirm = function()
    assert(sidebar.close())
    return 1
end
key("uu")
fixture.equal(third.id, api.state.current().id)
fixture.equal(-1, vim.fn.jobwait({ third_job }, 0)[1])
assert(sidebar.open())
select("third")
vim.fn.confirm = function(message, choices)
    assert(message:find("third", 1, true) and choices:find("Stop", 1, true))
    return 1
end
key("uu")
assert(api.state.current() == nil)
assert(not vim.api.nvim_buf_is_valid(third_buf))
assert(vim.fn.jobwait({ third_job }, 3000)[1] ~= -1)
assert(sidebar.is_open())
assert_transient_excluded()
assert(sidebar.close())
