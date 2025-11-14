---@class Opts
---@field path string | nil
---@field attach_after_enter boolean | nil
---@field prompt_title string | nil
---@field _dirs SessionsList | nil
---@field _marker string | nil
return {
    path = "~/sessions/",
    attach_after_enter = false,
    prompt_title = "🗃️ All sessions",
    _marker = "FOR_MARKER",
    _dirs = {}
}
