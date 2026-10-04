local actions = require("telescope._extensions.sess.actions")
local conf = require("telescope.config").values

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
    blocked = "TelescopeResultsWarning",
    done = "TelescopeResultsSpecialComment",
    unknown = "TelescopeResultsWarning",
    focused = "TelescopeResultsIdentifier",
    stale = "TelescopeResultsWarning",
}

config.values = {
    prompt_title = "All Sessions",
    display = {
        show_metadata = true,
        show_agent_summary = true,
        path_style = "full",
        highlights = default_highlights,
    },
    preview = {
        enabled = true,
        width = 0.35,
        show_snapshot_summary = true,
        show_agents = true,
    },
    action_help = {
        enabled = true,
        key = "?",
        footer = true,
        descriptions = {},
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
            ["<CR>"] = actions.enter,
        },
        ["n"] = {
            ["dd"] = actions.delete_session,
            ["uu"] = actions.unload_session,
            ["rr"] = actions.rename_session,
            ["<C-b>"] = actions.mark_session,
            ["<Tab>"] = actions.toggle_pin_session,
            ["<CR>"] = actions.enter,
        },
    },
    active_mappings = {
        ["i"] = {
            ["<Tab>"] = actions.toggle_active,
            ["<S-Tab>"] = actions.toggle_all_active,
            ["<CR>"] = actions.active_enter,
            ["<C-b>"] = actions.mark_session,
        },
        ["n"] = {
            ["<Tab>"] = actions.toggle_active,
            ["<S-Tab>"] = actions.toggle_all_active,
            ["<CR>"] = actions.active_enter,
            ["<C-b>"] = actions.mark_session,
        },
    },
}

config.setup = function(ext_config)
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
        for _, key in ipairs({ "enabled", "show_snapshot_summary", "show_agents" }) do
            if preview[key] ~= nil and type(preview[key]) ~= "boolean" then
                error("sess.nvim: preview." .. key .. " must be a boolean")
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
        for _, key in ipairs({ "show_metadata", "show_agent_summary" }) do
            if display[key] ~= nil and type(display[key]) ~= "boolean" then
                error("sess.nvim: display." .. key .. " must be a boolean")
            end
        end
        if display.path_style ~= nil and not path_styles[display.path_style] then
            error('sess.nvim: display.path_style must be "full", "relative", or "short"')
        end
        if display.highlights ~= nil then
            if type(display.highlights) ~= "table" then
                error("sess.nvim: display.highlights must be a table")
            end
            for name, group in pairs(display.highlights) do
                if type(name) ~= "string" or type(group) ~= "string" or group == "" then
                    error("sess.nvim: display highlight groups must be non-empty strings")
                end
            end
        end
    end

    config.values = vim.tbl_deep_extend("force", config.values, ext_config or {})
end

return config
