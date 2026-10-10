fixture.setup()

package.loaded["telescope.actions"] = { close = function() end }
package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
        return nil
    end,
}
package.loaded["telescope.finders"] = {
    new_table = function(value)
        return value
    end,
}
package.loaded["telescope.config"] = {
    values = { generic_sorter = function() end },
}
package.loaded["telescope.previewers"] = {
    new_buffer_previewer = function(options)
        return options
    end,
}

local config = require("telescope._extensions.sess.config")
local actions = require("telescope._extensions.sess.actions")
local help = require("telescope._extensions.sess.help")
local action_help = { action_help = config.values.action_help }

local regular_footer = help.footer("regular", "i", config.values.mappings, action_help)
assert(regular_footer:find("<CR>", 1, true))
assert(regular_footer:find("<Tab>", 1, true))
assert(regular_footer:find("<C-d>", 1, true))
assert(regular_footer:find("?", 1, true))

local normal_footer = help.footer("regular", "n", config.values.mappings, action_help)
assert(normal_footer:find("dd", 1, true))
assert(normal_footer:find("rr", 1, true))
assert(not normal_footer:find("<C-r> rename", 1, true))

local new_footer = help.footer(
    "regular",
    "i",
    config.values.mappings,
    action_help,
    { directory = true, path = "/tmp/new" }
)
assert(new_footer:find("<Tab>", 1, true))
assert(new_footer:find("<CR>", 1, true))

local active_lines = table.concat(
    help.lines("active", config.values.active_mappings, action_help, {
        kind = "placeholder",
    }),
    "\n"
)
assert(active_lines:find("all", 1, true))
assert(not active_lines:find("Assign mark", 1, true))

local custom_action = function() end
local custom_mappings = { i = { ["<C-x>"] = custom_action }, n = {} }
local custom_footer = help.footer("regular", "i", custom_mappings, action_help)
assert(custom_footer:find("<C-x> Run action", 1, true))

local conflict_footer = help.footer(
    "regular",
    "i",
    { i = { ["?"] = actions.mark_session } },
    action_help
)
assert(conflict_footer:find("? mark", 1, true))
assert(not conflict_footer:find("? actions", 1, true))

local same_label_lines = table.concat(
    help.lines(
        "regular",
        {
            i = { ["<C-x>"] = actions.mark_session },
            n = { ["<C-x>"] = actions.rename_session },
        },
        { action_help = { descriptions = { ["<C-x>"] = "Same label" } } }
    ),
    "\n"
)
assert(same_label_lines:find("Insert mode", 1, true))
assert(same_label_lines:find("Normal mode", 1, true))

local original_columns = vim.o.columns
vim.o.columns = 12
local narrow_footer = help.footer("regular", "i", config.values.mappings, action_help)
assert(vim.fn.strdisplaywidth(narrow_footer) <= vim.o.columns - 4)

local narrow_conflict_footer = help.footer(
    "regular",
    "i",
    { i = { ["?"] = actions.mark_session } },
    action_help
)
assert(not narrow_conflict_footer:find("? actions", 1, true))
vim.o.columns = original_columns

-- Footer text is bounded by the active floating window, not the full editor.
local footer_buf = vim.api.nvim_create_buf(false, true)
local footer_win = vim.api.nvim_open_win(footer_buf, true, {
    relative = "editor",
    row = 1,
    col = 1,
    width = 12,
    height = 3,
})
package.loaded["telescope.state"] = {
    get_status = function()
        return { picker = { results_win = footer_win } }
    end,
}
local floating_footer = help.footer("regular", "i", config.values.mappings, action_help)
assert(vim.fn.strdisplaywidth(floating_footer) <= 8)

-- Final footer shortening uses display cells and must not split a multibyte key.
vim.api.nvim_win_set_width(footer_win, 7)
local unicode_footer = help.footer("regular", "i", { i = { ["界界"] = actions.mark_session } }, {
    action_help = { key = false },
})
assert(vim.fn.strdisplaywidth(unicode_footer) <= 3)
assert(unicode_footer == "界…", unicode_footer)
package.loaded["telescope.state"] = nil
vim.api.nvim_win_close(footer_win, true)
vim.api.nvim_buf_delete(footer_buf, { force = true })

-- Telescope closes a picker on BufLeave. Sess suspends that ownership before
-- entering the help popup, so the prompt remains available while help is open.
local prompt_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_open_win(prompt_buf, true, {
    relative = "editor",
    row = 1,
    col = 1,
    width = 24,
    height = 3,
})
vim.api.nvim_create_augroup("PickerInsert", { clear = true })
vim.api.nvim_create_autocmd("BufLeave", {
    group = "PickerInsert",
    buffer = prompt_buf,
    callback = function()
        vim.api.nvim_buf_delete(prompt_buf, { force = true })
    end,
})
help.show(prompt_buf, "regular", config.values.mappings, action_help)
assert(vim.api.nvim_buf_is_valid(prompt_buf))
vim.api.nvim_buf_delete(prompt_buf, { force = true })

-- A configured action owns its key in that mode; help is only installed in
-- the mode where the key remains free.
local picker_options = {}
package.loaded["telescope.pickers"] = {
    new = function(options)
        picker_options[#picker_options + 1] = options
        return { find = function() end }
    end,
}
local pickers = require("telescope._extensions.sess.pickers")
config.setup({ mappings = { i = { ["?"] = actions.mark_session } } })
pickers.sess()
local mapped = {}
picker_options[1].attach_mappings(1, function(mode, key, callback)
    mapped[mode .. ":" .. key] = callback
end)
assert(mapped["i:?"] == config.values.mappings.i["?"])
assert(type(mapped["n:?"]) == "function")

config.setup({ action_help = { key = false, footer = false } })
assert(help.help_key({ action_help = config.values.action_help }) == nil)
assert(help.footer("regular", "i", config.values.mappings, {
    action_help = config.values.action_help,
}) == nil)

config.setup({ action_help = false })
assert(help.help_key({ action_help = false }) == nil)
assert(help.footer("regular", "i", config.values.mappings, { action_help = false }) == nil)
