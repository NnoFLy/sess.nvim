---@class sessionizer.Separators
---@field main string
---@field path string

---@class sessionizer.Consts
---@field path string
---@field prefix string
---@field separators sessionizer.Separators
return {
    path = vim.fn.stdpath("data") .. "/sessionizer/sessions/",
    prefix = "SESSION",
    separators = {
        main = ":SP:",
        path = ":SL:"
    },
}
