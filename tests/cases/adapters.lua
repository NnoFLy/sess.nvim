fixture.setup()

local api = require("sess.api")

local _, _, a = api.session.create(fixture.directory("a"))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved" })

local _, _, b = api.session.create(fixture.directory("b"))
vim.notify = function() end
require("sess.ui.command").setup()
vim.cmd("Sess load " .. a.id)
fixture.equal(a.id, api.state.current().id)
fixture.equal(buf, vim.api.nvim_get_current_buf())
package.loaded["telescope.actions"] = { close = function() end }
package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
        return { value = b }
    end,
}

package.loaded["telescope.finders"] = {
    new_table = function(value)
        return value
    end,
}

require("telescope._extensions.sess.actions").enter(0)
fixture.equal(b.id, api.state.current().id)
assert(vim.bo[buf].modified and not vim.bo[buf].buflisted)

local saves = 0
vim.api.nvim_create_autocmd("User", {
    pattern = "SessSaved",
    callback = function()
        saves = saves + 1
    end,
})

require("sess.autocmd").setup({ auto_save = true, smart_auto_load = false, exclude_filetypes = {} })
vim.api.nvim_exec_autocmds("VimLeavePre", {})
fixture.equal(1, saves)
require("sess.autocmd").setup({ auto_save = false, smart_auto_load = false })

-- Deleting the current session changes the editor layout. Close the picker
-- first and do not refresh it after its windows have been removed.
local prompt = vim.api.nvim_create_buf(false, true)
local picker_win = vim.api.nvim_open_win(prompt, true, {
    relative = "editor",
    row = 1,
    col = 1,
    width = 20,
    height = 4,
})

local closed, refreshed = false, false
package.loaded["telescope.actions"].close = function()
    closed = true
    vim.api.nvim_win_close(picker_win, true)
end

package.loaded["telescope.actions.state"].get_current_picker = function()
    return {
        refresh = function()
            assert(vim.api.nvim_win_is_valid(picker_win), "refreshing a closed picker")
            refreshed = true
        end,
    }
end

local confirm = vim.fn.confirm
local picker_actions = require("telescope._extensions.sess.actions")
vim.fn.confirm = function()
    return 2
end

picker_actions.delete_session(prompt)
assert(not closed and not refreshed)
vim.fn.confirm = function()
    return 1
end

package.loaded["telescope.actions.state"].get_selected_entry = function()
    return { value = a }
end

picker_actions.delete_session(prompt)
assert(not closed and refreshed)
fixture.equal(b.id, api.state.current().id)
refreshed = false
package.loaded["telescope.actions.state"].get_selected_entry = function()
    return { value = b }
end

picker_actions.delete_session(prompt)
vim.fn.confirm = confirm
assert(closed and not refreshed)
fixture.equal(nil, api.state.current())
