local M = {}

local GROUP = "SessNvim"

local autocmds = {
    ---@param group integer
    smart_auto_load = function (group)
        vim.api.nvim_create_autocmd("VimEnter", {
            group = group,
            callback = function()
                vim.schedule(function()
                    if vim.fn.argc() ~= 0 then
                        return
                    end

                    local api = require("sess.api")
                    local log = require("sess.log")
                    local cwd = vim.fs.normalize(vim.fn.getcwd())
                    local found, lookup_err, item = api.session.get_by_path(cwd)
                    if not found then
                        log.error(lookup_err or "Failed to find auto-load session")
                        return
                    end

                    local ok, err
                    if item then
                        ok, err = api.session.load(item)
                    else
                        ok, err = api.session.create(cwd)
                    end

                    if not ok then
                        log.error(err or "Failed to initialize session for current directory")
                    end
                end)
            end,
        })
    end,

    ---@param group integer
    ---@param opts Sess.Opts
    auto_save = function (group, opts)
        vim.api.nvim_create_autocmd("VimLeavePre", {
            group = group,
            callback = function()
                local state = require("sess.api").state
                if not state.current() then
                    return
                end

                local filetype = vim.bo.filetype
                if vim.list_contains(opts.exclude_filetypes, filetype) then
                    return
                end

                local ok, err = require("sess.api").session.save()
                if not ok then
                    require("sess.log").error(err or "Failed to auto save session")
                end
            end,
        })
    end,
}

---@param opts Sess.Opts
function M.setup(opts)
    local group = vim.api.nvim_create_augroup(GROUP, { clear = true })

    if opts.smart_auto_load then
        autocmds.smart_auto_load(group)
    end

    if opts.auto_save then
        autocmds.auto_save(group, opts)
    end
end

return M
