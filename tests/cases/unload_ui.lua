fixture.setup()

local api = require("sess.api")
local _, _, a = api.session.create(fixture.directory("a"), { name = "alpha" })
local _, _, b = api.session.create(fixture.directory("b"), { name = "beta" })
vim.notify = function() end
require("sess.ui.command").setup()

fixture.equal({ "unload", "unmark" }, vim.fn.getcompletion("Sess un", "cmdline"))
fixture.equal({ "alpha", "beta" }, vim.fn.getcompletion("Sess unload ", "cmdline"))
fixture.equal({ "alpha" }, vim.fn.getcompletion("Sess unload al", "cmdline"))
fixture.equal({}, vim.fn.getcompletion("Sess unload alpha ", "cmdline"))
vim.cmd("Sess unload alpha")
fixture.equal(b.id, api.state.current().id)
fixture.equal({ api.state.current() }, api.state.active())
vim.cmd("Sess unload " .. b.metadata.cwd)
fixture.equal(nil, api.state.current())
assert(api.session.load(a))
vim.cmd("Sess unload")
fixture.equal(nil, api.state.current())
assert(api.session.load(a))
local a_buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(a_buf, 0, -1, false, { "unsaved a" })
assert(api.session.load(b))
local b_buf = vim.api.nvim_get_current_buf()

local selected = { value = a }
local closed, refreshed = false, false
local prompt = vim.api.nvim_create_buf(false, true)
local picker_win = vim.api.nvim_open_win(prompt, true, {
    relative = "editor",
    row = 1,
    col = 1,
    width = 20,
    height = 4,
})

package.loaded["telescope.actions"] = {
    close = function()
        closed = true
        vim.api.nvim_win_close(picker_win, true)
    end,
}
package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
        return selected
    end,
    get_current_picker = function()
        return {
            refresh = function()
                assert(vim.api.nvim_win_is_valid(picker_win), "refreshing a closed picker")
                refreshed = true
            end,
        }
    end,
}
package.loaded["telescope.finders"] = {
    new_table = function(options)
        return options
    end,
}
package.loaded["telescope.config"] = { values = { generic_sorter = function() end } }

local actions = require("telescope._extensions.sess.actions")
local config = require("telescope._extensions.sess.config")
fixture.equal(actions.unload_session, config.values.mappings.i["<C-u>"])
fixture.equal(actions.unload_session, config.values.mappings.n.uu)

-- Missing entries and configured directories are not unload targets.
for _, entry in ipairs({ {}, { value = { metadata = { cwd = fixture.root } } } }) do
    selected = entry
    actions.unload_session(prompt)
    assert(not closed and not refreshed)
end
selected = nil
actions.unload_session(prompt)
assert(not closed and not refreshed)

selected = { value = a }
vim.fn.confirm = function(_, buttons, default)
    fixture.equal("&Save\n&Discard\n&Cancel", buttons)
    fixture.equal(3, default)
    return 3
end
actions.unload_session(prompt)
assert(not closed and refreshed)
fixture.equal(2, #api.state.active())
assert(vim.api.nvim_buf_is_valid(a_buf) and vim.bo[a_buf].modified)
vim.fn.confirm = function()
    return 2
end
actions.unload_session(prompt)
assert(not closed and refreshed)
fixture.equal(b.id, api.state.current().id)
fixture.equal({ api.state.current() }, api.state.active())
assert(not vim.api.nvim_buf_is_valid(a_buf))

-- Failed operations leave the current session and picker intact.
refreshed = false
selected = { value = { id = "missing", metadata = { name = "missing" } } }
actions.unload_session(prompt)
assert(not closed and refreshed)
fixture.equal(b.id, api.state.current().id)

-- Current-session unload closes the picker before prompts and snapshotting.
refreshed = false
selected = { value = b }
vim.api.nvim_buf_set_lines(b_buf, 0, -1, false, { "unsaved b" })
vim.fn.confirm = function()
    assert(closed and not vim.api.nvim_win_is_valid(picker_win))
    return 2
end
local saved = false
vim.api.nvim_create_autocmd("User", {
    pattern = "SessSaved",
    callback = function()
        assert(closed and not vim.api.nvim_win_is_valid(picker_win))
        saved = true
    end,
})
actions.unload_session(prompt)
assert(closed and saved and not refreshed)
assert(not vim.api.nvim_buf_is_valid(b_buf))
fixture.equal(nil, api.state.current())
fixture.equal({}, api.state.active())
assert(api.session.load(b))
fixture.equal(1, #vim.api.nvim_list_wins())
