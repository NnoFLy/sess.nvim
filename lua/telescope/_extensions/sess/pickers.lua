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

local function clear_transient_action_status(picker)
    local status = picker and picker._sess_action_status
    if
        type(status) == "string"
        and not status:match("^Failed:")
        and not status:find("error", 1, true)
        and not status:find("diagnostic", 1, true)
    then
        picker._sess_action_status = nil
    end
end

local function picker_status_text(picker, kind, mappings, help_options, selected)
    local action_status = picker and picker._sess_action_status
    local options = picker and picker._sess_search_options or {}
    local prompt
    local ok, value = pcall(action_state.get_current_line)
    if ok then
        prompt = value
    end
    local count
    local manager = picker and picker.manager
    if manager and type(manager.num_results) == "function" then
        local count_ok, result = pcall(manager.num_results, manager)
        if count_ok and type(result) == "number" then
            count = result
        end
    end
    local feedback, filter = search.feedback(prompt or "", options, count)
    if picker then
        picker._sess_search_filter = filter
        picker._sess_search_count = count
        picker._sess_sort_mode = options.sort or "default"
    end
    local footer = help.footer(kind, vim.fn.mode(1), mappings, help_options, selected)
    local parts = {}
    if picker and kind == "active" and picker._sess_active_refresh_warning then
        parts[#parts + 1] = "Warning: " .. tostring(picker._sess_active_refresh_warning)
    end
    if action_status then
        parts[#parts + 1] = action_status
    end
    if feedback then
        parts[#parts + 1] = feedback
    end
    if footer then
        parts[#parts + 1] = footer
    end
    local text = table.concat(parts, "  ")
    if text == "" then
        return nil
    end
    local width
    if picker and type(picker.results_win) == "number" then
        local width_ok, result = pcall(vim.api.nvim_win_get_width, picker.results_win)
        if width_ok and result > 0 then
            width = result - 4
        end
    end
    if width and vim.fn.strdisplaywidth(text) > width then
        text = layout.truncate_end(text, math.max(1, width))
    end
    return text
end

local function apply_mappings(map, mappings)
    for mode, mode_mappings in pairs(mappings or {}) do
        for key, action in pairs(mode_mappings) do
            if action ~= false then
                map(mode, key, action)
            end
        end
    end
end

local function add_active_navigation_mappings(mappings, options)
    local active = vim.tbl_deep_extend("force", config.values.active or {}, options.active or {})
    local explicit_mappings = options.active_mappings ~= nil
    if type(config.validate_active) == "function" then
        local valid_active, active_err = config.validate_active(active)
        if not valid_active then
            error("sess.nvim: " .. active_err)
        end
    end

    mappings = vim.deepcopy(mappings or {})
    if active.header_navigation ~= false then
        local keys = {
            next = active.next_header_key,
            previous = active.previous_header_key,
        }
        local actions_by_direction = {
            next = actions.next_active_header,
            previous = actions.previous_active_header,
        }
        for _, mode in ipairs({ "i", "n" }) do
            mappings[mode] = mappings[mode] or {}
            for direction, key in pairs(keys) do
                local action = actions_by_direction[direction]
                if key ~= nil and key ~= false and key ~= "" and mappings[mode][key] == nil then
                    mappings[mode][key] = action
                end
            end
        end
    end

    -- Refresh is independent from header navigation. A refresh key is
    -- generated only for an unclaimed key, so a user's existing mapping
    -- always wins, including one supplied by an active_mappings override.
    local refresh_key = active.refresh_key
    if refresh_key ~= false and type(refresh_key) == "string" and refresh_key ~= "" then
        for _, mode in ipairs({ "i", "n" }) do
            mappings[mode] = mappings[mode] or {}
            if
                not explicit_mappings
                and refresh_key ~= "<C-r>"
                and mappings[mode]["<C-r>"] == actions.refresh_active
            then
                mappings[mode]["<C-r>"] = nil
            end
            if mappings[mode][refresh_key] == nil then
                mappings[mode][refresh_key] = actions.refresh_active
            end
        end
    elseif refresh_key == false then
        -- The built-in table historically contained <C-r>. Remove only that
        -- built-in action when explicitly disabled; never remove a user's
        -- replacement action.
        if not explicit_mappings then
            for _, mode in ipairs({ "i", "n" }) do
                if mappings[mode] and mappings[mode]["<C-r>"] == actions.refresh_active then
                    mappings[mode]["<C-r>"] = nil
                end
            end
        end
    end
    return mappings
end

local function add_cycle_sort_mapping(mappings, search_options)
    local cycle_sort = search_options and search_options.cycle_sort
    local cycle_keys = {}
    if cycle_sort == true then
        cycle_keys.i, cycle_keys.n = "<C-s>", "<C-s>"
    elseif type(cycle_sort) == "string" then
        cycle_keys.i, cycle_keys.n = cycle_sort, cycle_sort
    elseif type(cycle_sort) == "table" then
        cycle_keys.i, cycle_keys.n = cycle_sort.i, cycle_sort.n
    end
    if not next(cycle_keys) then
        return mappings
    end

    mappings = vim.deepcopy(mappings or {})
    for _, mode in ipairs({ "i", "n" }) do
        local key = cycle_keys[mode]
        mappings[mode] = mappings[mode] or {}
        -- A configured mapping always wins. false deliberately disables the
        -- generated action, while nil leaves the key available for cycling.
        if key ~= nil and key ~= false and key ~= "" and mappings[mode][key] == nil then
            mappings[mode][key] = actions.cycle_sort
        end
    end
    return mappings
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
    local search_options = vim.tbl_deep_extend(
        "force",
        config.values.search or {},
        options.search or {}
    )
    opts.preview = nil
    opts.action_help = nil
    opts.sorter = search.new_sorter(configured_sorter, search_options)
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
    local display_config = vim.tbl_deep_extend(
        "force",
        config.values.display or {},
        opts.display or {}
    )
    local search_options = vim.tbl_deep_extend(
        "force",
        config.values.search or {},
        opts.search or {}
    )
    local density_key = display_config.toggle_key
    if not restore_picker and density_key ~= false and density_key ~= nil then
        mappings = vim.deepcopy(mappings)
        for _, mode in ipairs({ "i", "n" }) do
            mappings[mode] = mappings[mode] or {}
            -- A configured Sess mapping always wins over the generated action.
            if mappings[mode][density_key] == nil then
                mappings[mode][density_key] = actions.toggle_display
            end
        end
    end
    if not restore_picker then
        mappings = add_cycle_sort_mapping(mappings, search_options)
    end
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

    local function display_options(width, result_width)
        local options = {
            available_width = width or layout.available_width(picker),
            result_width = result_width or layout.result_width(picker),
        }
        if picker._sess_display_mode then
            options.mode = picker._sess_display_mode
        end
        return options
    end

    local function refresh_preserving_selection(next_finder)
        clear_transient_action_status(picker)
        local key = selection.current_key(picker)
        -- Hydration and resize callbacks run after the picker is visible. A
        -- renderer can mutate Telescope before raising, so use the same
        -- transaction as lifecycle refreshes and retain the last good rows.
        return actions.transactional_refresh(picker, next_finder, key)
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
            local previous_snapshot = previous_finder_snapshot
            previous_finder_snapshot = snapshot or previous_finder_snapshot
            if not picker_is_alive() or type(picker.refresh) ~= "function" then
                return
            end
            local ok, refreshed = pcall(function()
                return refresh_preserving_selection(finder)
            end)
            if not ok or refreshed == false then
                -- The candidate snapshot belongs to the candidate rows. Keep
                -- it paired with those rows so a failed hydration cannot make
                -- a later retry render from uncommitted state.
                previous_finder_snapshot = previous_snapshot
            end
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
        local close_handled = false
        local function on_close()
            if close_handled then
                return
            end
            close_handled = true
            stop_hydration()
            actions.on_picker_close(picker)
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
                result_width = layout.initial_width(config.values.preview, preview_context(opts)),
            }, search_options)
        or finders.generate_new_finder({
            available_width = layout.initial_width(config.values.preview, preview_context(opts)),
            result_width = layout.initial_width(config.values.preview, preview_context(opts)),
        }, nil, nil, search_options)
    if not restore_picker then
        if opts.get_status_text == nil then
            picker_opts.get_status_text = function()
                local selected
                local ok, action_state_value = pcall(action_state.get_selected_entry)
                if ok and action_state_value then
                    selected = action_state_value.value
                end
                return picker_status_text(picker, kind, mappings, help_options, selected)
            end
        end
        picker_opts.on_input_filter_cb = function(prompt)
            clear_transient_action_status(picker)
            if path.is_path(prompt) then
                local display_opts = display_options()
                local updated_finder = hydrate_finder(function(callback, previous_snapshot)
                    return finders.generate_directory_finder(
                        prompt,
                        display_opts,
                        callback,
                        previous_snapshot,
                        search_options
                    )
                end)
                selection.queue(picker, updated_finder, selection.current_key(picker))
                path_mode = true
                picker._sess_path_mode = true
                return { updated_finder = updated_finder }
            end

            if path_mode then
                path_mode = false
                picker._sess_path_mode = false
                local display_opts = display_options()
                local updated_finder = hydrate_finder(function(callback, previous_snapshot)
                    return finders.generate_new_finder(
                        display_opts,
                        callback,
                        previous_snapshot,
                        search_options
                    )
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
            return picker_status_text(picker, kind, mappings, help_options, selected)
        end
    end

    picker_opts.attach_mappings = function(prompt_bufnr, map)
        for mode, mode_mappings in pairs(mappings or {}) do
            for key, action in pairs(mode_mappings) do
                if action ~= false then
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
    picker._sess_search_options = search_options
    picker._sess_sort_mode = search_options.sort or "default"
    picker:find()
    install_hydration_close_hooks()
    local preview_config = config.values.preview or {}
    update_preview_layout(picker, configured_previewer, preview_config, opts.previewer ~= nil)
    local display_opts = display_options()
    if type(picker.refresh) == "function" then
        if restore_picker then
            refresh_preserving_selection(finders.generate_deleted_finder(display_opts, search_options))
        elseif path_mode then
            local prompt = action_state.get_current_line() or ""
            refresh_preserving_selection(
                finders.generate_directory_finder(prompt, display_opts, nil, nil, search_options)
            )
        else
            refresh_preserving_selection(
                finders.generate_new_finder(display_opts, nil, nil, search_options)
            )
        end
    end
    if not restore_picker then
        hydrate_finder(function(callback, previous_snapshot)
            return finders.generate_new_finder(
                display_opts,
                callback,
                previous_snapshot,
                search_options
            )
        end)
    end
    picker._sess_layout_stop = layout.on_resize(picker, function(width, result_width)
        local preview_config = config.values.preview or {}
        update_preview_layout(picker, configured_previewer, preview_config, opts.previewer ~= nil)
        local display_opts = display_options(width, result_width)
        if restore_picker then
            refresh_preserving_selection(finders.generate_deleted_finder(display_opts, search_options))
        elseif path_mode then
            local prompt = action_state.get_current_line() or ""
            refresh_preserving_selection(
                finders.generate_directory_finder(prompt, display_opts, nil, nil, search_options)
            )
        else
            refresh_preserving_selection(
                finders.generate_new_finder(display_opts, nil, nil, search_options)
            )
        end
        if not restore_picker then
            if path_mode then
                local prompt = action_state.get_current_line() or ""
                hydrate_finder(function(callback, previous_snapshot)
                    return finders.generate_directory_finder(
                        prompt,
                        display_opts,
                        callback,
                        previous_snapshot,
                        search_options
                    )
                end)
            else
                hydrate_finder(function(callback, previous_snapshot)
                    return finders.generate_new_finder(
                        display_opts,
                        callback,
                        previous_snapshot,
                        search_options
                    )
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
    local search_options = vim.tbl_deep_extend(
        "force",
        config.values.search or {},
        opts.search or {}
    )
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
        { available_width = layout.initial_width(config.values.preview, preview_context(opts)) },
        search_options
    )
    picker_opts.prompt_title = finders.active_dashboard_title(initial_snapshot)
    picker_opts.finder = finder
    picker_opts.selection_strategy = "row"
    local active_mappings = opts.active_mappings or config.values.active_mappings
    active_mappings = add_active_navigation_mappings(active_mappings, opts)
    active_mappings = add_cycle_sort_mapping(active_mappings, search_options)
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
            return picker_status_text(
                picker,
                "active",
                active_mappings,
                active_help_options,
                selected
            )
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
    picker_opts.sorter = search.new_active_sorter(picker_opts.sorter, search_options)
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
    picker._sess_search_options = search_options
    picker._sess_sort_mode = search_options.sort or "default"
    picker:find()

    -- Active refresh owns polling cleanup, while this hook owns the action
    -- cancellation contract. Keep the callback one-shot because Telescope can
    -- report the same close through both buffer and window lifecycle events.
    local close_autocmds = {}
    local close_handled = false
    local function on_close()
        if close_handled then
            return
        end
        close_handled = true
        for _, autocmd in ipairs(close_autocmds) do
            pcall(vim.api.nvim_del_autocmd, autocmd)
        end
        close_autocmds = {}
        if type(picker._sess_layout_stop) == "function" then
            pcall(picker._sess_layout_stop)
            picker._sess_layout_stop = nil
        end
        actions.on_picker_close(picker)
    end
    if type(picker.prompt_bufnr) == "number" then
        close_autocmds[#close_autocmds + 1] = vim.api.nvim_create_autocmd(
            { "BufHidden", "BufWipeout" },
            { buffer = picker.prompt_bufnr, callback = on_close }
        )
    end
    for _, win in ipairs({ picker.prompt_win, picker.results_win }) do
        if type(win) == "number" then
            close_autocmds[#close_autocmds + 1] = vim.api.nvim_create_autocmd(
                "WinClosed",
                { pattern = tostring(win), callback = on_close }
            )
        end
    end

    local preview_config = config.values.preview or {}
    update_preview_layout(picker, configured_previewer, preview_config, opts.previewer ~= nil)
    local layout_finder, layout_rows = finders.generate_active_finder_from_snapshot(
        initial_snapshot,
        expanded,
        active_expand,
        {
            available_width = layout.available_width(picker),
            result_width = layout.result_width(picker),
        },
        search_options
    )
    if type(picker.refresh) == "function" then
        picker:refresh(layout_finder, { reset_prompt = false })
        rows = layout_rows
    end
    picker._sess_layout_stop = layout.on_resize(picker, function()
        local preview_config = config.values.preview or {}
        update_preview_layout(picker, configured_previewer, preview_config, opts.previewer ~= nil)
    end)
    picker._sess_active_commit_title = function(snapshot)
        local title = finders.active_dashboard_title(snapshot)
        picker.prompt_title = title
        local prompt_border = picker.layout
            and picker.layout.prompt
            and picker.layout.prompt.border
        if prompt_border and type(prompt_border.change_title) == "function" then
            prompt_border:change_title(title)
        end
    end
    require("sess.ui.active_refresh").start(picker, function(expanded_by_id, done)
        picker._sess_active_loading = true
        return finders.generate_active_finder_async(
            expanded_by_id,
            picker._sess_active_expand,
            function(finder, next_rows, snapshot)
                picker._sess_active_loading = false
                preview.invalidate(picker)
                -- The transactional poller commits the title only after the
                -- candidate refresh succeeds. Keep the fallback mutation for
                -- lightweight test/integration adapters that do not use the
                -- transactional active-refresh implementation.
                done(finder, next_rows, snapshot)
                if not picker._sess_active_refresh_transactional then
                    picker._sess_active_commit_title(snapshot)
                end
            end,
            picker._sess_active_snapshot,
            {
                available_width = layout.available_width(picker),
                result_width = layout.result_width(picker),
            },
            picker._sess_search_options
        )
    end, rows, picker_opts.poll_interval)
end

return M
