local M = {}

function M.setup_auto_load()
    local commands = require("sess.commands")
    local session = require("sess.session")

    vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
            vim.schedule(function()
                if vim.fn.argc() ~= 0 then
                    return
                end

                local cwd = vim.fs.normalize(vim.fn.getcwd())
                local s = session.get_by_path(cwd)
                if s then
                    commands.load(s)
                else
                    commands.create(cwd)
                end
            end)
        end,
    })
end

function M.setup_auto_save()
    local commands = require("sess.commands")
    local opts = require("sess").get_opts()
    local state = require("sess.state")

    vim.api.nvim_create_autocmd("VimLeavePre", {
        callback = function()
            if vim.list_contains(opts.exclude_filetypes, vim.bo.filetype) then
                return
            end
            if not state.get_current_session() then
                return
            end
            commands.save()
        end,
    })
end

return M
