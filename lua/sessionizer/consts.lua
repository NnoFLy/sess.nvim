---@class Separators
---@field main string
---@field path string

---@class Consts
---@field path string
---@field prefix string
---@field separators Separators
return {
    path = vim.fn.stdpath("data") .. "/sessionizer/sessions/",
    prefix = "SESSION",
    separators = {
        main = ":SP:",
        path = ":SL:"
    },
}
