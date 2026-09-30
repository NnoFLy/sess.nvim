local actions = require("telescope._extensions.sess.actions")
local conf = require("telescope.config").values

local config = {}

local active_expand_modes = {
    all = true,
    current = true,
    none = true,
}

config.values = {
    prompt_title = "All sessions",
    active_expand = "all",
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
            ["<CR>"] = actions.enter,
        },
        ["n"] = {
            ["dd"] = actions.delete_session,
            ["uu"] = actions.unload_session,
            ["rr"] = actions.rename_session,
            ["<Tab>"] = actions.toggle_pin_session,
            ["<CR>"] = actions.enter,
        },
    },
}

config.setup = function(ext_config)
    local active_expand = ext_config and ext_config.active_expand
    if active_expand ~= nil and not active_expand_modes[active_expand] then
        error('sess.nvim: active_expand must be "all", "current", or "none"')
    end

    config.values = vim.tbl_deep_extend("force", config.values, ext_config or {})
end

return config
