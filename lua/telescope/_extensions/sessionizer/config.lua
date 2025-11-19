local actions = require("telescope._extensions.sessionizer.actions")
local conf = require("telescope.config").values

local config = {}

config.values = {
    prompt_title = "🗃️ All sessions",
    sorter = conf.generic_sorter(),
    mappings = {
        ["i"] = {
            ["<C-d>"] = actions.delete_session,
            ["<C-r>"] = actions.rename_session,
            ["<CR>"] = actions.enter,
        },
        ["n"] = {
            ["dd"] = actions.delete_session,
            ["rr"] = actions.rename_session,
            ["<CR>"] = actions.enter,
        },
    },
}

config.setup = function(ext_config)
    config.values = vim.tbl_deep_extend("force", config.values, ext_config or {})
end

return config
