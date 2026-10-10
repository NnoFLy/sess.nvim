fixture.setup()

local _, _, session = require("sess.api").session.create(fixture.directory("hydration"))

local selected
package.loaded["telescope.actions"] = { close = function() end }
package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
        return selected
    end,
    get_current_picker = function()
        return _G.hydration_picker
    end,
}
package.loaded["telescope.config"] = {
    values = {
        generic_sorter = function() return {} end,
        selection_caret = "> ",
    },
}
package.loaded["telescope.finders"] = {
    new_table = function(value) return value end,
}
package.loaded["telescope.previewers"] = {
    new_buffer_previewer = function() return {} end,
}

local picker_instances = {}
package.loaded["telescope.pickers"] = {
    new = function(options)
        local prompt_bufnr = vim.api.nvim_create_buf(false, true)
        local results_bufnr = vim.api.nvim_create_buf(false, true)
        local prompt_win = vim.api.nvim_open_win(prompt_bufnr, false, {
            relative = "editor",
            row = 1,
            col = 1,
            width = 20,
            height = 2,
        })
        local results_win = vim.api.nvim_open_win(results_bufnr, false, {
            relative = "editor",
            row = 3,
            col = 1,
            width = 20,
            height = 2,
        })
        local picker = {
            finder = options.finder,
            prompt_bufnr = prompt_bufnr,
            prompt_win = prompt_win,
            results_bufnr = results_bufnr,
            results_win = results_win,
            selection_caret = "> ",
            refresh_count = 0,
        }
        function picker:find() end
        function picker:refresh(finder)
            self.finder = finder
            self.refresh_count = self.refresh_count + 1
        end
        picker_instances[#picker_instances + 1] = picker
        return picker
    end,
}

local finders = require("telescope._extensions.sess.finders")
local hydration_callback
finders.generate_new_finder = function(_, callback)
    if callback then
        hydration_callback = callback
    end
    return { results = { { id = "base" } } }, callback and function() end or nil
end

local pickers = require("telescope._extensions.sess.pickers")
pickers.sess()
local closed_picker = picker_instances[1]
local refreshes = closed_picker.refresh_count
assert(type(hydration_callback) == "function")
vim.api.nvim_exec_autocmds("BufHidden", { buffer = closed_picker.prompt_bufnr })
hydration_callback({ results = { { id = "late" } } }, nil, {})
assert(closed_picker.refresh_count == refreshes, "closed picker was refreshed")

pickers.sess()
local picker = picker_instances[2]
_G.hydration_picker = picker
local stale_callback = hydration_callback
refreshes = picker.refresh_count
selected = { value = session }
require("telescope._extensions.sess.actions").toggle_pin_session(picker.prompt_bufnr)
assert(picker.refresh_count == refreshes + 1)
stale_callback({ results = { { id = "stale" } } }, nil, {})
assert(picker.refresh_count == refreshes + 1, "mutation hydration overwrote refreshed rows")

for _, item in ipairs(picker_instances) do
    if vim.api.nvim_win_is_valid(item.prompt_win) then
        vim.api.nvim_win_close(item.prompt_win, true)
    end
    if vim.api.nvim_win_is_valid(item.results_win) then
        vim.api.nvim_win_close(item.results_win, true)
    end
    if vim.api.nvim_buf_is_valid(item.prompt_bufnr) then
        vim.api.nvim_buf_delete(item.prompt_bufnr, { force = true })
    end
    if vim.api.nvim_buf_is_valid(item.results_bufnr) then
        vim.api.nvim_buf_delete(item.results_bufnr, { force = true })
    end
end
_G.hydration_picker = nil
