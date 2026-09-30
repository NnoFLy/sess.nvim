local pickers = require("telescope.pickers")
local action_state = require("telescope.actions.state")

local config = require("telescope._extensions.sess.config")
local finders = require("telescope._extensions.sess.finders")
local actions = require("telescope._extensions.sess.actions")
local path = require("sess.ui.path")
local state = require("sess.api").state

local function make_picker(opts, restore_picker)
    opts = opts or {}

    local picker_opts = vim.deepcopy(config.values)

    local current_session = state.current()
    if current_session then
        picker_opts.prompt_title = picker_opts.prompt_title .. " | " .. current_session.metadata.name
    end

    if picker_opts.theme and type(picker_opts.theme) == "table" then
        local theme_opts = picker_opts.theme
        picker_opts.theme = nil
        picker_opts = vim.tbl_deep_extend("force", theme_opts, picker_opts)
    end

    picker_opts.finder = restore_picker and finders.generate_deleted_finder() or finders.generate_new_finder()
    if not restore_picker then
        local path_mode = false
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
    local picker_opts = vim.deepcopy(config.values)
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
    local finder, rows = finders.generate_active_finder(expanded, active_expand)
    picker_opts.finder = finder
    picker_opts.selection_strategy = "row"
    picker_opts.get_status_text = function()
        return "<Tab> expand/collapse  <S-Tab> all  <Enter> switch/focus"
    end
    picker_opts.mappings = nil
    picker_opts.attach_mappings = function(_, map)
        map("i", "<Tab>", actions.toggle_active)
        map("n", "<Tab>", actions.toggle_active)
        map("i", "<S-Tab>", actions.toggle_all_active)
        map("n", "<S-Tab>", actions.toggle_all_active)
        map("i", "<CR>", actions.active_enter)
        map("n", "<CR>", actions.active_enter)
        return true
    end
    picker_opts = vim.tbl_deep_extend("force", picker_opts, opts)
    local picker = pickers.new(picker_opts)
    picker._sess_expanded = expanded
    picker._sess_active_expand = active_expand
    picker:find()
    require("sess.ui.active_refresh").start(picker, function(expanded_by_id)
        return finders.generate_active_finder(expanded_by_id, picker._sess_active_expand)
    end, rows)
end

return M
