local pickers = require("telescope.pickers")

local config = require("telescope._extensions.sessionizer.config")
local finders = require("telescope._extensions.sessionizer.finders")

return function(opts)
    opts = opts or {}

    local picker_opts = vim.deepcopy(config.values)

    if picker_opts.theme and type(picker_opts.theme) == "table" then
        local theme_opts = picker_opts.theme
        picker_opts.theme = nil
        picker_opts = vim.tbl_deep_extend("force", theme_opts, picker_opts)
    end

    picker_opts.finder = finders.generate_new_finder()
    picker_opts.attach_mappings = function(_, map)
        for mode, mappings in pairs(config.values.mappings or {}) do
            for key, action in pairs(mappings) do
                map(mode, key, action)
            end
        end
        return true
    end

    picker_opts.mappings = nil

    ---@diagnostic disable-next-line: cast-local-type
    picker_opts = vim.tbl_deep_extend("force", picker_opts, opts)

    pickers.new(picker_opts):find()
end
