fixture.setup()

package.loaded["telescope.finders"] = {
    new_table = function(options)
        return options
    end,
}
package.loaded["telescope._extensions.sess.config"] = {
    values = {
        display = {
            show_metadata = true,
            show_agent_summary = true,
            path_style = "full",
            highlights = {},
        },
        search = { sort = "default" },
    },
}

local layout = require("telescope._extensions.sess.layout")
assert(layout.display_width("界面") == 4)
local unicode_path = "/projects/界面/最後の-directory"
for _, width in ipairs({ 1, 2, 7, 13 }) do
    local shortened = layout.truncate_middle(unicode_path, width)
    assert(vim.fn.strdisplaywidth(shortened) <= width)
    assert(not shortened:find("\226\128\166\226", 1, true))
end
local fitted = layout.fit_parts({
    { text = "● " },
    { text = "界面", shrink_priority = 3, min_width = 1 },
    {
        text = "  /projects/界面/最後",
        truncate = "middle",
        shrink_priority = 1,
        min_width = 1,
        expendable = true,
    },
    {
        text = "  verbose agent information",
        truncate = "end",
        shrink_priority = 2,
        min_width = 0,
        expendable = true,
        omit_priority = 4,
    },
}, 20)
local fitted_text = ""
for _, part in ipairs(fitted) do
    fitted_text = fitted_text .. part.text
end
assert(vim.fn.strdisplaywidth(fitted_text) <= 20)
assert(fitted_text:find("界", 1, true))

-- Optional path and metadata must be discarded before the identity column is
-- shortened, even when the path is much longer than the available width.
local identity_first = layout.fit_parts({
    { text = "● " },
    { text = "session-name", shrink_priority = 3, min_width = 1 },
    { text = "  " },
    {
        text = "/projects/a/very/long/path/that/can/be-omitted",
        truncate = "middle",
        shrink_priority = 1,
        min_width = 1,
        expendable = true,
        omit_priority = 3,
    },
    { text = "  ★", omit_priority = 5 },
}, 20)
assert(identity_first[2].text == "session-name")

local finders = require("telescope._extensions.sess.finders")
local session = {
    id = "responsive",
    metadata = {
        name = "界面-frontend-session",
        cwd = "/home/example/projects/a-very-long/界面/final-directory",
        pinned = true,
    },
}
for _, width in ipairs({ 80, 100, 160 }) do
    local row = finders.format_session_display(session, {
        mark = "@frontend",
        mark_width = 10,
        name_width = vim.fn.strdisplaywidth(session.metadata.name),
        display = { available_width = width, path_style = "full", highlights = {} },
    })
    assert(vim.fn.strdisplaywidth(row) <= width, "row exceeds width " .. width)
    assert(row:find("界面%-frontend%-session"))
end

local rows = finders.build_active_entries(
    { session },
    {
        responsive = {
            {
                id = "agent",
                name = "代理",
                status = "working",
                info = "this verbose information must be shortened",
            },
        },
    },
    { responsive = true },
    nil,
    {},
    { responsive = "@frontend" },
    nil,
    { available_width = 28, path_style = "full", highlights = {} }
)
assert(#rows == 2)
assert(vim.fn.strdisplaywidth(rows[2].display) <= 28)
assert(rows[2].display:find("代理", 1, true))
assert(not rows[2].display:find("this verbose information must be shortened", 1, true))

-- The entry displayer pads each configured item. Empty fitted parts must not
-- be passed to it, or an omitted info part can overflow the layout width.
local rendered_item_sets = {}
package.loaded["telescope.pickers.entry_display"] = {
    create = function(options)
        rendered_item_sets[#rendered_item_sets + 1] = options.items
        return function(values)
            local rendered = {}
            for index, value in ipairs(values) do
                local width = options.items[index].width
                rendered[#rendered + 1] = value[1]
                    .. string.rep(" ", math.max(0, width - vim.fn.strdisplaywidth(value[1])))
            end
            return table.concat(rendered)
        end
    end,
}
local active_finder = finders.generate_active_finder_from_snapshot({
    sessions = { session },
    agents_by_id = {
        responsive = {
            {
                id = "agent",
                name = "代理",
                status = "working",
                info = "this verbose information must be shortened",
            },
        },
    },
    focused_by_id = {},
    marks_by_id = { responsive = "@frontend" },
    current_id = nil,
    agents_loaded_by_id = { responsive = true },
    stale_by_id = {},
}, { responsive = true }, "all", {
    available_width = 28,
    path_style = "full",
    highlights = {},
})
local rendered_agent = active_finder.entry_maker(active_finder.results[2])
local rendered_agent_text = rendered_agent.display()
assert(vim.fn.strdisplaywidth(rendered_agent_text) <= 28)
assert(#rendered_item_sets > 0)

local original_columns = vim.o.columns
-- min_width=1 must not bypass Telescope's default horizontal preview_cutoff.
local preview_config = { enabled = true, width = 0.35, min_width = 1 }
vim.o.columns = 80
assert(layout.initial_width(preview_config) == 80)
vim.o.columns = 100
assert(layout.initial_width(preview_config) == 100)
vim.o.columns = 160
assert(layout.initial_width(preview_config) == 104)

-- A picker resize must update the preview layout, not just refresh its rows.
local config = require("telescope._extensions.sess.config")
config.values.prompt_title = "Sessions"
config.values.preview = preview_config
config.values.mappings = { i = {}, n = {} }
config.values.action_help = false
config.values.layout_config = {}
package.loaded["telescope.actions"] = {}
package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
        return nil
    end,
    get_current_line = function()
        return ""
    end,
}
package.loaded["telescope.previewers"] = {
    new_buffer_previewer = function()
        return {}
    end,
}
vim.o.columns = 160
vim.cmd("vnew")
local results_win = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_width(results_win, 50)
local results_bufnr = vim.api.nvim_win_get_buf(results_win)
local caret_picker = {
    results_win = results_win,
    layout = { results = { winid = results_win } },
    selection_caret = "界 ",
}
assert(layout.available_width(caret_picker) == 47)
local picker_instances = {}
package.loaded["telescope.pickers"] = {
    new = function(options)
        local picker = {
            prompt_bufnr = vim.api.nvim_create_buf(false, true),
            results_win = results_win,
            results_bufnr = results_bufnr,
            layout = {
                results = { winid = results_win },
                preview = options.previewer and { winid = results_win } or nil,
            },
            previewer = options.previewer,
            selection_caret = "",
            layout_config = options.layout_config,
            finder = options.finder,
        }
        function picker:find() end
        function picker:refresh(finder)
            self.finder = finder
        end
        function picker:full_layout_update()
            self.layout_updates = (self.layout_updates or 0) + 1
            self.layout.preview = self.previewer
                    and vim.o.columns >= 120
                or nil
            if self.layout.preview then
                self.layout.preview = { winid = results_win }
            end
        end
        picker_instances[#picker_instances + 1] = picker
        return picker
    end,
}
local pickers = require("telescope._extensions.sess.pickers")
assert(not layout.preview_fits(preview_config, 100, 1, { layout_strategy = "horizontal" }))
assert(layout.preview_fits(preview_config, 160, 1, { layout_strategy = "horizontal" }))
local api = require("sess.api")
local ordinary_directory = fixture.directory("responsive-action-with-a-very-long-directory-name")
local _, create_err, ordinary_session = api.session.create(ordinary_directory)
assert(ordinary_session, create_err)
local _, action_err, action_session = api.session.create(fixture.directory("responsive-action"))
assert(action_session, action_err)
vim.o.columns = 100
vim.api.nvim_win_set_width(results_win, 100)
pickers.sess()
local cutoff_picker = picker_instances[#picker_instances]
assert(cutoff_picker.previewer == nil)
vim.o.columns = 80
vim.api.nvim_win_set_width(results_win, 50)
pickers.sess()
local picker = picker_instances[#picker_instances]
local function ordinary_row(current_finder)
    for _, item in ipairs(current_finder.results or {}) do
        if item.id == ordinary_session.id then
            local row = current_finder.entry_maker(item)
            if type(row.display) == "function" then
                row.display = row.display()
            end
            return row
        end
    end
end
local narrow_row = ordinary_row(picker.finder)
assert(narrow_row and narrow_row.display)
local narrow_width = vim.api.nvim_win_get_width(picker.results_win)
assert(vim.fn.strdisplaywidth(narrow_row.display) <= narrow_width)
assert(picker and picker.previewer == nil)
vim.o.columns = 80
vim.api.nvim_exec_autocmds("VimResized", {})
-- A resize while the active result window remains narrow keeps preview hidden.
assert(picker.previewer == nil, "previewer remained at width " .. vim.api.nvim_win_get_width(picker.results_win))
assert(picker.layout_updates == nil)
-- Preview eligibility must use the result width after adding the preview.
vim.o.columns = 100
vim.api.nvim_win_set_width(picker.results_win, 100)
vim.api.nvim_exec_autocmds("VimResized", {})
assert(picker.previewer == nil)
assert(picker.layout_updates == nil)
local wide_row = ordinary_row(picker.finder)
assert(wide_row and wide_row.display ~= narrow_row.display)
assert(vim.fn.strdisplaywidth(wide_row.display) <= 100)
vim.o.columns = 160
vim.api.nvim_exec_autocmds("VimResized", {})
assert(picker.previewer ~= nil)
assert(picker.layout_updates == 1)
-- Once a preview is active, eligibility must use the current result width;
-- subtracting the preview fraction a second time would remove it immediately
-- from an otherwise wide picker.
vim.o.columns = 120
vim.api.nvim_win_set_width(picker.results_win, 80)
vim.api.nvim_exec_autocmds("VimResized", {})
assert(picker.previewer ~= nil)
assert(picker.layout_updates == 1)
vim.o.columns = 70
vim.api.nvim_win_set_width(picker.results_win, 70)
vim.api.nvim_exec_autocmds("VimResized", {})
assert(picker.previewer == nil, "previewer remained at width " .. vim.api.nvim_win_get_width(picker.results_win))
assert(picker.layout_updates == 2)

-- Caller-supplied previewers must survive responsive updates for both picker
-- variants instead of being replaced by Sess's generated previewer.
vim.o.columns = 160
vim.api.nvim_win_set_width(picker.results_win, 104)
pickers.sess()
local wide_picker = picker_instances[#picker_instances]
assert(wide_picker.previewer ~= nil)
assert(wide_picker.layout_updates == nil)
vim.api.nvim_exec_autocmds("VimResized", {})
assert(wide_picker.previewer ~= nil)
assert(wide_picker.layout_updates == nil)

vim.api.nvim_win_set_width(picker.results_win, 160)
local regular_previewer = { custom = true }
pickers.sess({ previewer = regular_previewer })
local regular_picker = picker_instances[#picker_instances]
assert(
    regular_picker.previewer == regular_previewer,
    "custom regular previewer replaced at width " .. vim.api.nvim_win_get_width(regular_picker.results_win)
)
vim.o.columns = 100
vim.api.nvim_win_set_width(results_win, 50)
local narrow_previewer = { custom = "narrow" }
pickers.sess({ previewer = narrow_previewer })
local narrow_picker = picker_instances[#picker_instances]
assert(narrow_picker.previewer == narrow_previewer)
pickers.active({ previewer = narrow_previewer })
local narrow_active_picker = picker_instances[#picker_instances]
assert(narrow_active_picker.previewer == narrow_previewer)
vim.api.nvim_exec_autocmds("VimResized", {})
assert(narrow_picker.previewer == narrow_previewer)
assert(narrow_active_picker.previewer == narrow_previewer)
assert(regular_picker.previewer == regular_previewer)

config.values.preview = { enabled = false, width = 0.35, min_width = 80 }
local disabled_previewer = { custom = "disabled" }
pickers.active({ previewer = disabled_previewer })
local disabled_picker = picker_instances[#picker_instances]
assert(disabled_picker.previewer == disabled_previewer)
pickers.sess({ previewer = disabled_previewer })
local disabled_regular_picker = picker_instances[#picker_instances]
assert(disabled_regular_picker.previewer == disabled_previewer)
vim.api.nvim_exec_autocmds("VimResized", {})
assert(disabled_picker.previewer == disabled_previewer)
assert(disabled_regular_picker.previewer == disabled_previewer)
assert(narrow_picker.previewer == narrow_previewer)

local active_previewer = { custom = true }
config.values.preview = preview_config
vim.o.columns = 160
vim.api.nvim_win_set_width(results_win, 160)
pickers.active({ previewer = active_previewer })
local active_picker = picker_instances[#picker_instances]
assert(active_picker.previewer == active_previewer)
for _, open_picker in ipairs({ pickers.sess, pickers.active }) do
    open_picker({ previewer = false })
    local no_preview_picker = picker_instances[#picker_instances]
    assert(no_preview_picker.previewer == false)
    vim.api.nvim_exec_autocmds("VimResized", {})
    assert(no_preview_picker.previewer == false)
end

-- Mutating a row must use the active result width rather than terminal width.
local selected = { value = action_session }
local measured_width = vim.api.nvim_win_get_width(picker.results_win)
local action_state = package.loaded["telescope.actions.state"]
action_state.get_current_picker = function()
    return picker
end
action_state.get_selected_entry = function()
    return selected
end
local finders_module = require("telescope._extensions.sess.finders")
local original_generate_new_finder = finders_module.generate_new_finder
local action_width
finders_module.generate_new_finder = function(options)
    action_width = options.available_width
    return { results = {} }
end
require("telescope._extensions.sess.actions").toggle_pin_session(0)
assert(action_width == measured_width)
finders_module.generate_new_finder = original_generate_new_finder

picker._sess_layout_stop()
vim.api.nvim_buf_delete(picker.prompt_bufnr, { force = true })
vim.o.columns = original_columns
