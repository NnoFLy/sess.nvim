fixture.setup()

package.loaded["telescope.actions"] = { close = function() end }
local action_state = {
    get_selected_entry = function()
        return nil
    end,
}
package.loaded["telescope.actions.state"] = action_state
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

assert(config.values.mappings.i["<C-y>"] == actions.copy_path)
assert(config.values.mappings.n["<C-y>"] == actions.copy_path)
assert(config.values.active_mappings == nil)
local active_mappings = vim.deepcopy(config.values.mappings)
for _, mode in ipairs({ "i", "n" }) do
    active_mappings[mode]["<Tab>"] = actions.toggle_active
    active_mappings[mode]["<S-Tab>"] = actions.toggle_all_active
    active_mappings[mode]["<CR>"] = actions.active_enter
    active_mappings[mode]["<C-o>"] = actions.focus_agent
end
local regular_entries = help.entries(
    "regular",
    "i",
    config.values.mappings,
    action_help,
    { id = "session", metadata = { cwd = "/tmp/session" } }
)
local active_session_entries = help.entries(
    "active",
    "i",
    active_mappings,
    action_help,
    { kind = "session", session_id = "session" }
)
local inactive_agent_entries = help.entries(
    "active",
    "i",
    active_mappings,
    action_help,
    { kind = "agent", session_id = "session", agent_id = "agent", current = false }
)
local active_agent_entries = help.entries(
    "active",
    "i",
    active_mappings,
    action_help,
    { kind = "agent", session_id = "session", agent_id = "agent", current = true }
)
local function has_id(entries, id)
    for _, entry in ipairs(entries) do
        if entry.id == id then
            return true
        end
    end
    return false
end
assert(has_id(regular_entries, "copy_path"))
assert(not has_id(active_session_entries, "refresh"))
assert(not has_id(active_session_entries, "focus"))
assert(not has_id(inactive_agent_entries, "focus"))
assert(has_id(active_agent_entries, "focus"))

local global_regular_mappings = {
    i = {
        ["<C-g>"] = actions.toggle_display,
        ["<C-s>"] = actions.cycle_sort,
    },
}
local global_regular_entries = help.entries(
    "regular",
    "i",
    global_regular_mappings,
    action_help,
    { directory = true, path = "/tmp/new" }
)
assert(has_id(global_regular_entries, "density"))
assert(has_id(global_regular_entries, "cycle_sort"))
local global_active_entries = help.entries(
    "active",
    "i",
    {
        i = {
            ["<C-r>"] = actions.refresh_active,
            ["<C-s>"] = actions.cycle_sort,
        },
    },
    action_help,
    { kind = "placeholder" }
)
assert(has_id(global_active_entries, "refresh"))
assert(has_id(global_active_entries, "cycle_sort"))

local copied
local original_setreg = vim.fn.setreg
vim.fn.setreg = function(register, value)
    copied = { register, value }
end
action_state.get_selected_entry = function()
    return { value = { id = "session", metadata = { cwd = "/complete/session/path" } } }
end
actions.copy_path(1)
assert(copied[1] == "+")
assert(copied[2] == "/complete/session/path")
vim.fn.setreg = original_setreg

action_state.get_selected_entry = function()
    return nil
end

assert(help.footer("regular", "i", config.values.mappings, action_help) == "? - help")
assert(help.footer("regular", "n", config.values.mappings, action_help) == "? - help")
assert(
    help.footer("regular", "i", config.values.mappings, action_help, {
        directory = true,
        path = "/tmp/new",
    }) == "? - help"
)

local active_lines = table.concat(
    help.lines("active", active_mappings, action_help, {
        kind = "placeholder",
    }),
    "\n"
)
assert(active_lines:find("all", 1, true))
assert(not active_lines:find("Assign mark", 1, true))

local custom_action = function() end
local custom_mappings = { i = { ["<C-x>"] = custom_action }, n = {} }
assert(help.footer("regular", "i", custom_mappings, action_help) == "? - help")

assert(
    help.footer(
        "regular",
        "i",
        { i = { ["?"] = actions.mark_session } },
        action_help
    ) == nil
)

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

-- Help remains a single, stable hint regardless of the picker width.
local original_columns = vim.o.columns
vim.o.columns = 12
assert(help.footer("regular", "i", config.values.mappings, action_help) == "? - help")
vim.o.columns = original_columns

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
local created_picker
package.loaded["telescope.pickers"] = {
    new = function(options)
        picker_options[#picker_options + 1] = options
        created_picker = { find = function() end }
        return created_picker
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

-- The prompt status stays free of action, search, and result-count ghost text.
created_picker.manager = { num_results = function() return 3 end }
created_picker._sess_search_options = vim.tbl_deep_extend(
    "force",
    {},
    created_picker._sess_search_options or {},
    { sort = "name" }
)
created_picker._sess_action_status = "Failed: write failed"
assert(picker_options[1].get_status_text() == "? - help")

config.setup({ action_help = { key = false, footer = false } })
assert(help.help_key({ action_help = config.values.action_help }) == nil)
assert(help.footer("regular", "i", config.values.mappings, {
    action_help = config.values.action_help,
}) == nil)

config.setup({ action_help = false })
assert(help.help_key({ action_help = false }) == nil)
assert(help.footer("regular", "i", config.values.mappings, { action_help = false }) == nil)

local replacement = function() end
config.setup({ mappings = { i = { ["<C-y>"] = replacement } } })
assert(config.values.mappings.i["<C-y>"] == replacement)

-- Sort cycling is generated for active pickers without replacing configured
-- mappings or explicit disablement.
config.setup({ search = { cycle_sort = true } })
pickers.active()
local active_picker_options = picker_options[#picker_options]
local active_mapped = {}
active_picker_options.attach_mappings(1, function(mode, key, callback)
    active_mapped[mode .. ":" .. key] = callback
end)
assert(active_mapped["i:<C-s>"] == actions.cycle_sort)
assert(active_mapped["n:<C-s>"] == actions.cycle_sort)
local active_cycle_footer = help.footer(
    "active",
    "i",
    { i = { ["<C-s>"] = actions.cycle_sort } },
    { action_help = { enabled = true, footer = true, key = "?" } }
)
assert(active_cycle_footer == "? - help")
config.setup({
    search = { cycle_sort = true },
    mappings = { i = { ["<C-s>"] = false } },
})
pickers.active()
local disabled_active_options = picker_options[#picker_options]
local disabled_mapped = {}
disabled_active_options.attach_mappings(1, function(mode, key, callback)
    disabled_mapped[mode .. ":" .. key] = callback
end)
assert(disabled_mapped["i:<C-s>"] == nil)
assert(disabled_mapped["n:<C-s>"] == actions.cycle_sort)

-- A failed regular sort refresh must leave the displayed finder and status
-- state describing the previous sort mode.
local finders = require("telescope._extensions.sess.finders")
local original_generate_new = finders.generate_new_finder
local old_finder = { results = { "old" } }
local cycle_picker = {
    finder = old_finder,
    _sess_help_kind = "regular",
    _sess_search_options = { sort = "default" },
    _sess_sort_mode = "default",
    _sess_action_status = "Sort: default",
    prompt = "sort prompt",
    refresh = function(self, finder)
        -- Telescope adapters may partially commit the candidate before raising.
        self.finder = finder
        self._sess_search_options = { sort = "candidate" }
        self._sess_sort_mode = "candidate"
        self._sess_action_status = "candidate status"
        error("injected sort refresh failure")
    end,
}
action_state.get_current_picker = function()
    return cycle_picker
end
finders.generate_new_finder = function()
    return { results = { "new" } }
end
actions.cycle_sort(1)
assert(cycle_picker._sess_search_options.sort == "default")
assert(cycle_picker._sess_sort_mode == "default")
assert(cycle_picker.finder == old_finder)
assert(cycle_picker._sess_action_status == "Sort: default")
finders.generate_new_finder = original_generate_new

-- A failed density refresh must restore the mode describing the committed rows.
local display_picker = {
    finder = old_finder,
    _sess_display_mode = "detailed",
    refresh = function()
        error("injected density refresh failure")
    end,
}
action_state.get_current_picker = function()
    return display_picker
end
actions.toggle_display(1)
assert(display_picker._sess_display_mode == "detailed")
