---@class Sess.Separators
---@field main string
---@field path string

---@class Sess.Consts
---@field path string
---@field prefix string
---@field separators Sess.Separators
return {
    path = vim.fn.stdpath("data") .. "/sess/sessions/",
    prefix = "SESSION",
    separators = {
        main = ":SP:",
        path = ":SL:"
    },
}
