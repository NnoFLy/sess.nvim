local telescope = require("sess.ui.telescope")

---@param ctx Sess.CommandContext
---@return boolean
return function(ctx)
    return telescope.list()
end
