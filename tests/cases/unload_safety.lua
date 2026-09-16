fixture.setup()

local api = require("sess.api")
local _, _, item = api.session.create(fixture.directory("project"))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "original edit" })

-- Confirmation callbacks cannot approve data that appeared after the prompt.
local ok, err = api.session.unload(item, {
    confirm = function(request)
        fixture.equal("buffers", request.kind)
        local nested, nested_err = api.session.unload(item)
        assert(not nested and nested_err:match("in progress"))
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "new edit" })
        return "discard"
    end,
})
assert(not ok and err:match("changed during unload"))
fixture.equal(item.id, api.state.current().id)
fixture.equal({ "new edit" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

local added
ok, err = api.session.unload(item, {
    confirm = function()
        added = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(added, 0, -1, false, { "not approved" })
        return "discard"
    end,
})
assert(not ok and err:match("changed during unload"))
assert(vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_valid(added))

-- Outgoing save observers run before teardown and must not bypass consent.
local observer = vim.api.nvim_create_autocmd("User", {
    pattern = "SessSaved",
    callback = function()
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "post-save edit" })
    end,
})
ok, err = api.session.unload(item, {
    confirm = function()
        return "discard"
    end,
})
vim.api.nvim_del_autocmd(observer)
assert(not ok and err:match("changed during unload"))
fixture.equal(item.id, api.state.current().id)
fixture.equal({ "post-save edit" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))

-- Recheck each buffer: deleting an earlier buffer may run user autocommands.
local wipe = vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    callback = function()
        vim.api.nvim_buf_set_lines(added, 0, -1, false, { "late edit" })
    end,
})
ok, err = api.session.unload(item, {
    confirm = function()
        return "discard"
    end,
})
pcall(vim.api.nvim_del_autocmd, wipe)
assert(not ok and err:match("changed during unload"))
assert(vim.api.nvim_buf_is_valid(added) and vim.bo[added].modified)
fixture.equal({ "late edit" }, vim.api.nvim_buf_get_lines(added, 0, -1, false))
assert(api.session.unload(item, {
    confirm = function()
        return "discard"
    end,
}))

-- An exited terminal has no running job to confirm.
local _, _, finished = api.session.create(fixture.directory("finished"))
local terminal = vim.api.nvim_get_current_buf()
local job = vim.fn.jobstart({ "sh", "-c", "exit 0" }, { term = true })
fixture.equal(0, vim.fn.jobwait({ job }, 3000)[1])
assert(api.session.unload(finished, {
    confirm = function()
        error("no live jobs or unsaved text")
    end,
}))
assert(not vim.api.nvim_buf_is_valid(terminal))

-- A running terminal alone still requires explicit consent. A newly started
-- terminal during confirmation cannot inherit the original job's approval.
local _, _, live = api.session.create(fixture.directory("live"))
terminal = vim.api.nvim_get_current_buf()
job = vim.fn.jobstart({ "sh", "-c", "sleep 60" }, { term = true })
ok, err = api.session.unload(live)
assert(not ok and err:match("running terminal jobs"))
fixture.equal(-1, vim.fn.jobwait({ job }, 0)[1])
local second, second_job
ok, err = api.session.unload(live, {
    confirm = function(request)
        fixture.equal("jobs", request.kind)
        vim.cmd("enew")
        second = vim.api.nvim_get_current_buf()
        second_job = vim.fn.jobstart({ "sh", "-c", "sleep 60" }, { term = true })
        return "stop"
    end,
})
assert(not ok and err:match("changed during unload"))
fixture.equal(-1, vim.fn.jobwait({ job }, 0)[1])
fixture.equal(-1, vim.fn.jobwait({ second_job }, 0)[1])
assert(api.session.unload(live, {
    confirm = function(request)
        fixture.equal("jobs", request.kind)
        fixture.equal(2, #request.buffers)
        return "stop"
    end,
}))
assert(not vim.api.nvim_buf_is_valid(terminal))
assert(not vim.api.nvim_buf_is_valid(second))
assert(vim.fn.jobwait({ job, second_job }, 3000)[1] ~= -1)
