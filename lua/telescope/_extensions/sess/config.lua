local actions = require("telescope._extensions.sess.actions")
local conf = require("telescope.config").values
local search = require("telescope._extensions.sess.search")

local config = {}

local active_expand_modes = {
    all = true,
    current = true,
    none = true,
}

local path_styles = {
    full = true,
    relative = true,
    short = true,
}

local display_modes = {
    compact = true,
    detailed = true,
    auto = true,
}

local status_highlights = {
    blocked = { group = "SessStatusBlocked", link = "DiagnosticWarn" },
    unknown = { group = "SessStatusUnknown", link = "DiagnosticInfo" },
    stale = { group = "SessStatusStale", link = "DiagnosticHint" },
}

local default_highlights = {
    current = "TelescopeResultsIdentifier",
    active = "TelescopeResultsIdentifier",
    inactive = "TelescopeResultsComment",
    new = "TelescopeResultsSpecialComment",
    mark = "TelescopeResultsNumber",
    name = "TelescopeResultsNormal",
    cwd = "TelescopeResultsComment",
    metadata = "TelescopeResultsComment",
    agent = "TelescopeResultsIdentifier",
    working = "TelescopeResultsIdentifier",
    idle = "TelescopeResultsComment",
    blocked = status_highlights.blocked.group,
    done = "TelescopeResultsSpecialComment",
    unknown = status_highlights.unknown.group,
    focused = "TelescopeResultsIdentifier",
    stale = status_highlights.stale.group,
}

config.values = {
    prompt_title = "All Sessions",
    display = {
        mode = "detailed",
        compact_width = 100,
        icons = true,
        ascii_fallback = false,
        toggle_key = "<C-g>",
        show_metadata = true,
        show_agent_summary = true,
        path_style = "full",
        highlights = default_highlights,
    },
    preview = {
        enabled = true,
        width = 0.35,
        min_width = 80,
        show_snapshot_summary = true,
        show_agents = true,
        show_editor_summary = true,
        show_action_hint = true,
        max_agents = 8,
    },
    action_help = {
        enabled = true,
        key = "?",
        footer = true,
        descriptions = {},
    },
    search = {
        fields = {
            "name",
            "cwd",
            "mark",
            "pinned",
            "last",
            "current",
            "active",
            "agent",
            "status",
            "info",
        },
        filters = true,
        sort = "default",
        show_count = true,
        show_sort = true,
        cycle_sort = false,
    },
    active = {
        -- The key is added only when it is free in the active picker mapping;
        -- set false to disable the generated manual-refresh mapping.
        refresh_key = "<C-r>",
        header_navigation = true,
        next_header_key = "<C-j>",
        previous_header_key = "<C-k>",
    },
    active_expand = "none",
    poll_interval = 1000,
    sorting_strategy = "ascending",
    layout_config = {
        prompt_position = "top",
    },
    sorter = conf.generic_sorter(),
    mappings = {
        ["i"] = {
            ["<C-d>"] = actions.delete_session,
            ["<C-u>"] = actions.unload_session,
            ["<Tab>"] = actions.toggle_pin_session,
            ["<C-r>"] = actions.rename_session,
            ["<C-b>"] = actions.mark_session,
            ["<C-y>"] = actions.copy_path, -- false disables copy-path action
            ["<CR>"] = actions.enter,
        },
        ["n"] = {
            ["dd"] = actions.delete_session,
            ["uu"] = actions.unload_session,
            ["rr"] = actions.rename_session,
            ["<C-b>"] = actions.mark_session,
            ["<C-y>"] = actions.copy_path, -- false disables copy-path action
            ["<Tab>"] = actions.toggle_pin_session,
            ["<CR>"] = actions.enter,
        },
    },
}

function config.validate_active(active)
    active = active or {}
    local function configured_key(value)
        return value ~= nil and value ~= false and value ~= ""
    end

    local next_key = active.next_header_key
    local previous_key = active.previous_header_key
    if configured_key(next_key) and configured_key(previous_key) and next_key == previous_key then
        return false, "active.next_header_key and active.previous_header_key must differ"
    end
    if active.header_navigation ~= false and configured_key(active.refresh_key) then
        if active.refresh_key == next_key or active.refresh_key == previous_key then
            return false, "active.refresh_key must not collide with active header navigation keys"
        end
    end
    return true
end

config.setup = function(ext_config)
    local configured_search = ext_config and ext_config.search
    if configured_search ~= nil then
        if type(configured_search) ~= "table" then
            error("sess.nvim: search must be a table")
        end
        local valid_search, search_err = search.validate(configured_search)
        if not valid_search then
            error("sess.nvim: " .. search_err)
        end
    end

    local active = ext_config and ext_config.active
    if active ~= nil then
        if type(active) ~= "table" then
            error("sess.nvim: active must be a table")
        end
        if
            active.refresh_key ~= nil
            and active.refresh_key ~= false
            and (type(active.refresh_key) ~= "string" or active.refresh_key == "")
        then
            error("sess.nvim: active.refresh_key must be a non-empty string, false, or nil")
        end
        if active.header_navigation ~= nil and type(active.header_navigation) ~= "boolean" then
            error("sess.nvim: active.header_navigation must be a boolean")
        end
        for _, key in ipairs({ "next_header_key", "previous_header_key" }) do
            if
                active[key] ~= nil
                and active[key] ~= false
                and (type(active[key]) ~= "string" or active[key] == "")
            then
                error("sess.nvim: active." .. key .. " must be a non-empty string, false, or nil")
            end
        end
        local merged_active = vim.tbl_deep_extend(
            "force",
            vim.deepcopy(config.values.active or {}),
            active
        )
        local valid_active, active_err = config.validate_active(merged_active)
        if not valid_active then
            error("sess.nvim: " .. active_err)
        end
    end

    local active_expand = ext_config and ext_config.active_expand
    if active_expand ~= nil and not active_expand_modes[active_expand] then
        error('sess.nvim: active_expand must be "all", "current", or "none"')
    end

    local poll_interval = ext_config and ext_config.poll_interval
    if
        poll_interval ~= nil
        and (
            type(poll_interval) ~= "number"
            or poll_interval <= 0
            or poll_interval % 1 ~= 0
        )
    then
        error("sess.nvim: poll_interval must be a positive integer in milliseconds")
    end

    local preview = ext_config and ext_config.preview
    if preview ~= nil then
        if type(preview) ~= "table" then
            error("sess.nvim: preview must be a table")
        end
        for _, key in ipairs({
            "enabled",
            "show_snapshot_summary",
            "show_agents",
            "show_editor_summary",
            "show_action_hint",
        }) do
            if preview[key] ~= nil and type(preview[key]) ~= "boolean" then
                error("sess.nvim: preview." .. key .. " must be a boolean")
            end
        end
        if preview.max_agents ~= nil then
            if
                type(preview.max_agents) ~= "number"
                or preview.max_agents ~= preview.max_agents
                or preview.max_agents == math.huge
                or preview.max_agents == -math.huge
                or preview.max_agents < 1
                or preview.max_agents % 1 ~= 0
            then
                error("sess.nvim: preview.max_agents must be a positive integer")
            end
        end
        if preview.min_width ~= nil then
            if
                type(preview.min_width) ~= "number"
                or preview.min_width ~= preview.min_width
                or preview.min_width == math.huge
                or preview.min_width == -math.huge
                or preview.min_width < 1
                or preview.min_width % 1 ~= 0
            then
                error("sess.nvim: preview.min_width must be a positive integer")
            end
        end
        if preview.width ~= nil then
            if
                type(preview.width) ~= "number"
                or preview.width ~= preview.width
                or preview.width <= 0
                or preview.width > 1
                or preview.width == math.huge
            then
                error("sess.nvim: preview.width must be a number between 0 and 1")
            end
        end
    end

    local action_help = ext_config and ext_config.action_help
    if action_help ~= nil and action_help ~= false then
        if type(action_help) ~= "table" then
            error("sess.nvim: action_help must be a table or false")
        end
        for _, key in ipairs({ "enabled", "footer" }) do
            if action_help[key] ~= nil and type(action_help[key]) ~= "boolean" then
                error("sess.nvim: action_help." .. key .. " must be a boolean")
            end
        end
        if
            action_help.key ~= nil
            and action_help.key ~= false
            and (type(action_help.key) ~= "string" or action_help.key == "")
        then
            error("sess.nvim: action_help.key must be a non-empty string, false, or nil")
        end
        if action_help.descriptions ~= nil and type(action_help.descriptions) ~= "table" then
            error("sess.nvim: action_help.descriptions must be a table")
        end
    end

    local display = ext_config and ext_config.display
    if display ~= nil then
        if type(display) ~= "table" then
            error("sess.nvim: display must be a table")
        end
        for _, key in ipairs({
            "icons",
            "ascii_fallback",
            "show_metadata",
            "show_agent_summary",
        }) do
            if display[key] ~= nil and type(display[key]) ~= "boolean" then
                error("sess.nvim: display." .. key .. " must be a boolean")
            end
        end
        if display.mode ~= nil and not display_modes[display.mode] then
            error('sess.nvim: display.mode must be "compact", "detailed", or "auto"')
        end
        if display.compact_width ~= nil then
            if
                type(display.compact_width) ~= "number"
                or display.compact_width ~= display.compact_width
                or display.compact_width == math.huge
                or display.compact_width == -math.huge
                or display.compact_width < 1
                or display.compact_width % 1 ~= 0
            then
                error("sess.nvim: display.compact_width must be a positive integer")
            end
        end
        if
            display.toggle_key ~= nil
            and display.toggle_key ~= false
            and (type(display.toggle_key) ~= "string" or display.toggle_key == "")
        then
            error("sess.nvim: display.toggle_key must be a non-empty string, false, or nil")
        end
        if display.path_style ~= nil and not path_styles[display.path_style] then
            error('sess.nvim: display.path_style must be "full", "relative", or "short"')
        end
        if display.highlights ~= nil then
            if type(display.highlights) ~= "table" then
                error("sess.nvim: display.highlights must be a table")
            end
            for name, group in pairs(display.highlights) do
                if type(name) ~= "string" or not default_highlights[name] then
                    error("sess.nvim: unknown display highlight field: " .. tostring(name))
                end
                if type(group) ~= "string" or group == "" then
                    error("sess.nvim: display highlight groups must be non-empty strings")
                end
            end
        end
    end

    for _, highlight in pairs(status_highlights) do
        vim.api.nvim_set_hl(0, highlight.group, { default = true, link = highlight.link })
    end

    config.values = vim.tbl_deep_extend("force", config.values, ext_config or {})
end

return config
