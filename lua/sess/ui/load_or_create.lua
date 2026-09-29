local api = require("sess.api")
local path = require("sess.ui.path")

local M = {}

---@param cwd string
---@return boolean, string?, Sess.Session?, string[]?
function M.run(cwd)
    local normalized, path_err = path.normalize_existing(cwd)
    if not normalized then
        return false, path_err
    end

    local found, lookup_err, existing = api.session.get_by_path(normalized)
    if not found then
        return false, lookup_err
    end

    if existing then
        return api.session.load(existing.id)
    end

    local ok, err, item, diagnostics = api.session.create(normalized)
    if not ok then
        return ok, err, item, diagnostics
    end

    local explorer_ok, explorer_err = pcall(vim.cmd, {
        cmd = "edit",
        args = { normalized },
        magic = { file = false, bar = false },
    })
    if not explorer_ok then
        diagnostics = diagnostics or {}
        diagnostics[#diagnostics + 1] = "failed to open file explorer: " .. tostring(explorer_err)
    end

    return ok, err, item, diagnostics
end

return M
