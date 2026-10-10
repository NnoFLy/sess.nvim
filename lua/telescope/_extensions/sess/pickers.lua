local pickers = require("telescope.pickers")
local action_state = require("telescope.actions.state")

local config = require("telescope._extensions.sess.config")
local finders = require("telescope._extensions.sess.finders")
local search = require("telescope._extensions.sess.search")
local actions = require("telescope._extensions.sess.actions")
local help = require("telescope._extensions.sess.help")
local preview = require("telescope._extensions.sess.preview")
local layout = require("telescope._extensions.sess.layout")
local selection = require("telescope._extensions.sess.selection")
local path = require("sess.ui.path")
local state = require("sess.api").state

local function apply_mappings(map, mappings)
    for mode, mode_mappings in pairs(mappings or {}) do
        for key, action in pairs(mode_mappings) do
            map(mode, key, action)
        end
    end
end

local function update_preview_layout(picker, previewer, preview_config, explicit)
    -- An explicit caller previewer has precedence over responsive defaults,
    -- including when Sess's preview is disabled or the result is too narrow.
    if explicit then
        picker.previewer = previewer
        return
    end
    if not previewer then
        return
    end
    local result_width = layout.available_width(picker)
    local preview_active = layout.has_preview_window(picker)
    local available_width = preview_active
            and result_width
        or layout.preview_result_width(preview_config, nil, result_width)
    local next_previewer = layout.preview_fits(preview_config, nil, available_width, picker)
            and previewer
        or nil
    local changed = picker.previewer ~= next_previewer
    picker.previewer = next_previewer
    picker.layout_config = picker.layout_config or {}
    picker.layout_config.preview_width = preview_config.width or 0.35
    if changed and type(picker.full_layout_update) == "function" then
        pcall(function()
            picker:full_layout_update()
        end)
    end
    -- Telescope may reject the previewer after the layout strategy applies
    -- preview_cutoff. Do not leave Sess's state saying a pane is available.
    if picker.previewer ~= nil and not layout.has_preview_window(picker) then
        picker.previewer = nil
    end
end

local function preview_context(options)
    options = options or {}
    return {
        layout_strategy = options.layout_strategy or config.values.layout_strategy,
        selection_caret = options.selection_caret,
        layout_config = vim.tbl_deep_extend(
            "force",
            config.values.layout_config or {},
            options.layout_config or {}
        ),
    }
end

local function picker_options(options)
    -- deepcopy does not preserve Telescope sorter's lifecycle metatable.
    local configured_sorter = config.values.sorter
    local opts = vim.deepcopy(config.values)
    local preview_config = opts.preview or {}
    opts.preview = nil
    opts.action_help = nil
    opts.sorter = search.new_sorter(configured_sorter, opts.search or {})
    opts.search = nil
    -- Telescope owns the preview buffer lifecycle. On narrow terminals the
    -- pane is omitted rather than taking space from the prompt and results.
    if preview_config.enabled ~= false then
        local previewer = preview.new(preview_config)
        opts._sess_previewer = previewer
        if
            previewer
                and layout.preview_fits(preview_config, nil, nil, preview_context(options))
            then
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

    local picker_opts = picker_options(opts)
    local kind = restore_picker and "restore" or "regular"
    local mappings = restore_picker and {
        i = { ["<CR>"] = actions.restore_session },
        n = { ["<CR>"] = actions.restore_session },
    } or opts.mappings or config.values.mappings
    local action_help = opts.action_help
    if action_help == nil then
        action_help = config.values.action_help
    end
    local help_options = { action_help = action_help }

    local picker
    local path_mode = false
    local finder_generation = 0
    local finder_cancel
    local previous_finder_snapshot
    local hydration_close_autocmds = {}

    local function invalidate_hydration()
        finder_generation = finder_generation + 1
        if finder_cancel then
            pcall(finder_cancel)
            finder_cancel = nil
        end
    end

    local function picker_is_alive()
        if not picker or picker.closed == true then
            return false
        end
        if type(picker.is_done) == "function" then
            local ok, done = pcall(picker.is_done, picker)
            if ok and done then
                return false
            end
        end
        for _, buf in ipairs({ picker.prompt_bufnr, picker.results_bufnr }) do
            if type(buf) == "number" then
                local ok, valid = pcall(vim.api.nvim_buf_is_valid, buf)
                if not ok or not valid then
                    return false
                end
            end
        end
        for _, win in ipairs({ picker.prompt_win, picker.results_win }) do
            if type(win) == "number" then
                local ok, valid = pcall(vim.api.nvim_win_is_valid, win)
                if not ok or not valid then
                    return false
                end
            end
        end
        return true
    end

    local function refresh_preserving_selection(next_finder)
        local key = selection.current_key(picker)
        selection.queue(picker, next_finder, key)
        picker:refresh(next_finder, { reset_prompt = false })
        if not selection.is_attached(picker) then
            selection.restore_pending(picker)
        end
    end

    local function hydrate_finder(generator)
        finder_generation = finder_generation + 1
        local generation = finder_generation
        if finder_cancel then
            pcall(finder_cancel)
            finder_cancel = nil
        end
        local finder, cancel = generator(function(finder, _, snapshot)
            if generation ~= finder_generation then
                return
            end
            previous_finder_snapshot = snapshot or previous_finder_snapshot
            if not picker_is_alive() or type(picker.refresh) ~= "function" then
                return
            end
            pcall(function()
                refresh_preserving_selection(finder)
            end)
        end, previous_finder_snapshot)
        finder_cancel = cancel
        return finder
    end

    local function stop_hydration()
        invalidate_hydration()
        for _, autocmd in ipairs(hydration_close_autocmds) do
            pcall(vim.api.nvim_del_autocmd, autocmd)
        end
        hydration_close_autocmds = {}
    end

    local function install_hydration_close_hooks()
        picker._sess_invalidate_finder_hydration = invalidate_hydration
        local function on_close()
            stop_hydration()
        end
        if type(picker.prompt_bufnr) == "number" then
            hydration_close_autocmds[#hydration_close_autocmds + 1] = vim.api.nvim_create_autocmd(
                { "BufHidden", "BufWipeout" },
                { buffer = picker.prompt_bufnr, callback = on_close }
            )
        end
        for _, win in ipairs({ picker.prompt_win, picker.results_win }) do
            if type(win) == "number" then
                hydration_close_autocmds[#hydration_close_autocmds + 1] = vim.api.nvim_create_autocmd(
                    "WinClosed",
                    { pattern = tostring(win), callback = on_close }
                )
            end
        end
    end
    local generated_previewer = picker_opts._sess_previewer
    picker_opts._sess_previewer = nil
    local current_session = state.current()
    if current_session then
        picker_opts.prompt_title = picker_opts.prompt_title .. " | " .. current_session.metadata.name
    end

    picker_opts.finder = restore_picker
            and finders.generate_deleted_finder({
                available_width = layout.initial_width(
                    config.values.preview,
                    preview_context(opts)
                ),
            })
        or finders.generate_new_finder({
            available_width = layout.initial_width(config.values.preview, preview_context(opts)),
        })
    if not restore_picker then
        if opts.get_status_text == nil then
            picker_opts.get_status_text = function()
                local selected
                local ok, action_state_value = pcall(action_state.get_selected_entry)
                if ok and action_state_value then
                    selected = action_state_value.value
                end
                local footer = help.footer(kind, vim.fn.mode(1), mappings, help_options, selected)
                return picker and picker._sess_action_status or footer
            end
        end
        picker_opts.on_input_filter_cb = function(prompt)
            if path.is_path(prompt) then
                local display_opts = {
                    available_width = layout.available_width(picker),
                }
                local updated_finder = hydrate_finder(function(callback, previous_snapshot)
                    return finders.generate_directory_finder(
                        prompt,
                        display_opts,
                        callback,
                        previous_snapshot
                    )
                end)
                selection.queue(picker, updated_finder, selection.current_key(picker))
                path_mode = true
                return { updated_finder = updated_finder }
            end

            if path_mode then
                path_mode = false
                local display_opts = {
                    available_width = layout.available_width(picker),
                }
                local updated_finder = hydrate_finder(function(callback, previous_snapshot)
                    return finders.generate_new_finder(display_opts, callback, previous_snapshot)
                end)
                selection.queue(picker, updated_finder, selection.current_key(picker))
                return { updated_finder = updated_finder }
            end

            return {}
        end
    elseif opts.get_status_text == nil then
        picker_opts.get_status_text = function()
            local selected
            local ok, action_state_value = pcall(action_state.get_selected_entry)
            if ok and action_state_value then
                selected = action_state_value.value
            end
            local footer = help.footer(kind, vim.fn.mode(1), mappings, help_options, selected)
            return picker and picker._sess_action_status or footer
        end
    end

    picker_opts.attach_mappings = function(prompt_bufnr, map)
        for mode, mode_mappings in pairs(mappings or {}) do
            for key, action in pairs(mode_mappings) do
                local mapped_action = action
                if
                    not restore_picker
                    and key == "<Tab>"
                    and type(action) == "function"
                then
                    local default_action = action
                    mapped_action = function(current_prompt_bufnr)
                        if path.is_path(action_state.get_current_line()) then
                            return actions.complete_path(current_prompt_bufnr)
                        end
                        return default_action(current_prompt_bufnr)
                    end
                end
                map(mode, key, mapped_action)
            end
        end

        local key = help.help_key(help_options)
        if key then
            for _, mode in ipairs({ "i", "n" }) do
                if not (mappings[mode] and mappings[mode][key] ~= nil) then
                    map(mode, key, function(current_prompt_bufnr)
                        actions.show_action_help(
                            current_prompt_bufnr,
                            kind,
                            mappings,
                            help_options
                        )
                    end)
                end
            end
        end
        return true
    end

    picker_opts.mappings = nil

    ---@diagnostic disable-next-line: cast-local-type
    picker_opts = vim.tbl_deep_extend("force", picker_opts, opts)
    -- Mappings are installed by attach_mappings so the help key can never
    -- replace a configured action.
    picker_opts.mappings = nil
    picker_opts.action_help = nil
    -- A caller's explicit previewer, including false, wins over the generated
    -- Sess previewer. The generated value is only a fallback when omitted.
    local configured_previewer
    if opts.previewer ~= nil then
        -- tbl_deep_extend recursively copies table-valued previewers. Restore
        -- the explicit object so Telescope receives exactly what the caller
        -- supplied, including false.
        picker_opts.previewer = opts.previewer
    end
    configured_previewer = picker_opts.previewer
    if configured_previewer == nil then
        configured_previewer = generated_previewer
    end

    picker = pickers.new(picker_opts)
    selection.attach(picker)
    picker._sess_help_kind = kind
    picker._sess_help_mappings = mappings
    picker._sess_help_options = help_options
    picker:find()
    install_hydration_close_hooks()
    local preview_config = config.values.preview or {}
    update_preview_layout(picker, configured_previewer, preview_config, opts.previewer ~= nil)
    local display_opts = { available_width = layout.available_width(picker) }
    if type(picker.refresh) == "function" then
        if restore_picker then
            refresh_preserving_selection(finders.generate_deleted_finder(display_opts))
        elseif path_mode then
            local prompt = action_state.get_current_line() or ""
            refresh_preserving_selection(finders.generate_directory_finder(prompt, display_opts))
        else
            refresh_preserving_selection(finders.generate_new_finder(display_opts))
        end
    end
    if not restore_picker then
        hydrate_finder(function(callback, previous_snapshot)
            return finders.generate_new_finder(display_opts, callback, previous_snapshot)
        end)
    end
    picker._sess_layout_stop = layout.on_resize(picker, function(width)
        local preview_config = config.values.preview or {}
        update_preview_layout(picker, configured_previewer, preview_config, opts.previewer ~= nil)
        local display_opts = { available_width = layout.available_width(picker, width) }
        if restore_picker then
            refresh_preserving_selection(finders.generate_deleted_finder(display_opts))
        elseif path_mode then
            local prompt = action_state.get_current_line() or ""
            refresh_preserving_selection(finders.generate_directory_finder(prompt, display_opts))
        else
            refresh_preserving_selection(finders.generate_new_finder(display_opts))
        end
        if not restore_picker then
            if path_mode then
                local prompt = action_state.get_current_line() or ""
                hydrate_finder(function(callback, previous_snapshot)
                    return finders.generate_directory_finder(
                        prompt,
                        display_opts,
                        callback,
                        previous_snapshot
                    )
                end)
            else
                hydrate_finder(function(callback, previous_snapshot)
                    return finders.generate_new_finder(display_opts, callback, previous_snapshot)
                end)
            end
        end
    end)
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
    local picker_opts = picker_options(opts)
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
        active_expand,
        { available_width = layout.initial_width(config.values.preview, preview_context(opts)) }
    )
    picker_opts.prompt_title = finders.active_dashboard_title(initial_snapshot)
    picker_opts.finder = finder
    picker_opts.selection_strategy = "row"
    local active_mappings = opts.active_mappings or config.values.active_mappings
    local active_action_help = opts.action_help
    if active_action_help == nil then
        active_action_help = config.values.action_help
    end
    local active_help_options = { action_help = active_action_help }
    local picker
    if opts.get_status_text == nil then
        picker_opts.get_status_text = function()
            local selected
            local ok, action_state_value = pcall(action_state.get_selected_entry)
            if ok and action_state_value then
                selected = action_state_value.value
            end
            local footer = help.footer(
                "active",
                vim.fn.mode(1),
                active_mappings,
                active_help_options,
                selected
            )
            return picker and picker._sess_action_status or footer
        end
    end
    picker_opts.mappings = nil
    picker_opts.attach_mappings = function(_, map)
        apply_mappings(map, active_mappings)
        local key = help.help_key(active_help_options)
        if key then
            for _, mode in ipairs({ "i", "n" }) do
                if not (active_mappings[mode] and active_mappings[mode][key] ~= nil) then
                    map(mode, key, function(prompt_bufnr)
                        actions.show_action_help(
                            prompt_bufnr,
                            "active",
                            active_mappings,
                            active_help_options
                        )
                    end)
                end
            end
        end
        return true
    end
    picker_opts = vim.tbl_deep_extend("force", picker_opts, opts)
    picker_opts.sorter = search.new_active_sorter(picker_opts.sorter, opts.search)
    picker_opts.mappings = nil
    picker_opts.action_help = nil
    local generated_previewer = picker_opts._sess_previewer
    picker_opts._sess_previewer = nil
    -- Preserve an explicitly supplied previewer (including false) rather than
    -- replacing it with the generated Sess previewer during layout updates.
    local configured_previewer
    if opts.previewer ~= nil then
        picker_opts.previewer = opts.previewer
    end
    configured_previewer = picker_opts.previewer
    if configured_previewer == nil then
        configured_previewer = generated_previewer
    end
    picker = pickers.new(picker_opts)
    selection.attach(picker)
    picker._sess_help_kind = "active"
    picker._sess_help_mappings = active_mappings
    picker._sess_help_options = active_help_options
    picker._sess_expanded = expanded
    picker._sess_active_expand = active_expand
    picker._sess_active_snapshot = initial_snapshot
    picker._sess_active_loading = true
    picker:find()
    local preview_config = config.values.preview or {}
    update_preview_layout(picker, configured_previewer, preview_config, opts.previewer ~= nil)
    local layout_finder, layout_rows = finders.generate_active_finder_from_snapshot(
        initial_snapshot,
        expanded,
        active_expand,
        { available_width = layout.available_width(picker) }
    )
    if type(picker.refresh) == "function" then
        picker:refresh(layout_finder, { reset_prompt = false })
        rows = layout_rows
    end
    picker._sess_layout_stop = layout.on_resize(picker, function()
        local preview_config = config.values.preview or {}
        update_preview_layout(picker, configured_previewer, preview_config, opts.previewer ~= nil)
    end)
    require("sess.ui.active_refresh").start(picker, function(expanded_by_id, done)
        picker._sess_active_loading = true
        return finders.generate_active_finder_async(
            expanded_by_id,
            picker._sess_active_expand,
            function(finder, next_rows, snapshot)
                picker._sess_active_loading = false
                local title = finders.active_dashboard_title(snapshot)
                picker.prompt_title = title
                local prompt_border = picker.layout
                    and picker.layout.prompt
                    and picker.layout.prompt.border
                if prompt_border and type(prompt_border.change_title) == "function" then
                    prompt_border:change_title(title)
                end
                done(finder, next_rows, snapshot)
            end,
            picker._sess_active_snapshot,
            { available_width = layout.available_width(picker) }
        )
    end, rows, picker_opts.poll_interval)
end

return M
