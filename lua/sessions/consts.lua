---@class Consts
---@field path string
---@field marker string
return {
    path = vim.fn.stdpath("data") .. "/sessions/",
    marker = "MARKER",
}
