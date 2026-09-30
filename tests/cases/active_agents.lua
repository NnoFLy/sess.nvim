fixture.setup()

local api = require("sess.api")
local _, _, session = api.session.create(fixture.directory("project"))
assert(api.session.load(session.id))

local terminal = vim.api.nvim_create_buf(false, true)
vim.api.nvim_open_term(terminal, {})
vim.b[terminal].terminal_job_id = 99
vim.api.nvim_win_set_buf(0, terminal)

local original_job_info = vim.fn.job_info
vim.fn.job_info = function()
    return { status = "run", cmd = { "codex" } }
end

package.loaded["telescope.finders"] = {
    new_table = function(value)
        return value
    end,
}

local finder = require("telescope._extensions.sess.finders").generate_active_finder({
    [session.id] = true,
})
assert(#finder.results == 2, vim.inspect(finder.results))
assert(finder.results[2].kind == "agent")
assert(finder.results[2].agent.name == "codex")
assert(finder.results[2].agent.target.bufnr == terminal)

local ok, err, registered = api.agent.register(nil, {
    id = "pi",
    name = "pi",
    bufnr = terminal,
    winid = vim.api.nvim_get_current_win(),
})
assert(ok, err)
assert(registered.target.bufnr == terminal)

local list_ok, list_err, listed = api.agent.list()
assert(list_ok, list_err)
assert(#listed == 1)
assert(listed[1].name == "pi")

vim.fn.job_info = original_job_info
