local pickers = require("telescope.pickers")
local action_state = require("telescope.actions.state")

local config = require("telescope._extensions.sess.config")
local finders = require("telescope._extensions.sess.finders")
local actions = require("telescope._extensions.sess.actions")
local preview = require("telescope._extensions.sess.preview")
local path = require("sess.ui.path")
local state = require("sess.api").state

local function apply_mappings(map, mappings)
    for mode, mode_mappings in pairs(mappings or {}) do
        for key, action in pairs(mode_mappings) do
            map(mode, key, action)
        end
    end
end

local function picker_options()
    local opts = vim.deepcopy(config.values)
    local preview_config = opts.preview or {}
    opts.preview = nil
    -- Telescope owns the preview buffer lifecycle. On narrow terminals the
    -- pane is omitted rather than taking space from the prompt and results.
    if preview_config.enabled ~= false and vim.o.columns >= 80 then
        local previewer = preview.new(preview_config)
        if previewer then
            opts.previewer = previewer
            opts.layout_config = vim.tbl_deep_extend(
                "force",
                opts.layout_config or {},
                { preview_width = preview_config.width or 0.35 }
            )
        end
    end
    if type(opts.theme) == "table" then
        local theme_opts = opts.theme
        opts.theme = nil
        opts = vim.tbl_deep_extend("force", theme_opts, opts)
    end
    return opts
end

local function make_picker(opts, restore_picker)
    opts = opts or {}

    local picker_opts = picker_options()

    local current_session = state.current()
    if current_session then
        picker_opts.prompt_title = picker_opts.prompt_title .. " | " .. current_session.metadata.name
    end

    picker_opts.finder = restore_picker and finders.generate_deleted_finder() or finders.generate_new_finder()
    if not restore_picker then
        local path_mode = false
        picker_opts.get_status_text = picker_opts.get_status_text or function()
            return "<Tab> pin/complete  <C-b> mark  <Enter> switch/load"
        end
        picker_opts.on_input_filter_cb = function(prompt)
            if path.is_path(prompt) then
                path_mode = true
                return { updated_finder = finders.generate_directory_finder(prompt) }
            end

            if path_mode then
                path_mode = false
                return { updated_finder = finders.generate_new_finder() }
            end

            return {}
        end
    end

    picker_opts.attach_mappings = function(_, map)
        if restore_picker then
            map("i", "<CR>", actions.restore_session)
            map("n", "<CR>", actions.restore_session)
        else
            for mode, mappings in pairs(config.values.mappings or {}) do
                for key, action in pairs(mappings) do
                    local mapped_action = action
                    if key == "<Tab>" and type(action) == "function" then
                        local default_action = action
                        mapped_action = function(prompt_bufnr)
                            if path.is_path(action_state.get_current_line()) then
                                return actions.complete_path(prompt_bufnr)
                            end
                            return default_action(prompt_bufnr)
                        end
                    end
                    map(mode, key, mapped_action)
                end
            end
        end
        return true
    end

    picker_opts.mappings = nil

    ---@diagnostic disable-next-line: cast-local-type
    picker_opts = vim.tbl_deep_extend("force", picker_opts, opts)

    pickers.new(picker_opts):find()
end

local M = {}

function M.sess(opts)
    return make_picker(opts, false)
end

function M.restore(opts)
    return make_picker(opts, true)
end

function M.active(opts)
    opts = opts or {}
    local picker_opts = picker_options()
    picker_opts.prompt_title = "Active Sessions"
    local active_expand = config.values.active_expand
    local expanded = {}
    local current = state.current()
    for _, session in ipairs(state.active()) do
        local should_expand = active_expand == "all"
        if active_expand == "current" then
            should_expand = current ~= nil and current.id == session.id
        end
        expanded[session.id] = should_expand
    end
    -- Show session headers before hydrating agents and marks so large active
    -- session sets stay responsive.
    local initial_snapshot = require("sess.api").active.initial_snapshot()
    local finder, rows = finders.generate_active_finder_from_snapshot(
        initial_snapshot,
        expanded,
        active_expand
    )
    picker_opts.finder = finder
    picker_opts.selection_strategy = "row"
    picker_opts.get_status_text = picker_opts.get_status_text or function()
        return "<Tab> expand/collapse  <S-Tab> all  <C-b> mark  <Enter> switch/focus"
    end
    picker_opts.mappings = nil
    picker_opts.attach_mappings = function(_, map)
        apply_mappings(map, config.values.active_mappings)
        return true
    end
    picker_opts = vim.tbl_deep_extend("force", picker_opts, opts)
    local picker = pickers.new(picker_opts)
    picker._sess_expanded = expanded
    picker._sess_active_expand = active_expand
    picker._sess_active_snapshot = initial_snapshot
    picker._sess_active_loading = true
    picker:find()
    require("sess.ui.active_refresh").start(picker, function(expanded_by_id, done)
        picker._sess_active_loading = true
        return finders.generate_active_finder_async(
            expanded_by_id,
            picker._sess_active_expand,
            function(finder, next_rows, snapshot)
                picker._sess_active_loading = false
                done(finder, next_rows, snapshot)
            end,
            picker._sess_active_snapshot
        )
    end, rows, picker_opts.poll_interval)
end

return M
