local M = {}

function M.check()
    local health = vim.health
    health.start("sess.nvim")
    if not require("sess.api.opts").is_setup() then
        health.error("sess.nvim is not initialized; call require('sess').setup()")
        return
    end

    health.ok("Setup completed")

    local storage = require("sess.storage")

    local root = storage.root()

    for _, path in ipairs({
        root,
        vim.fs.joinpath(root, "sessions"),
        vim.fs.joinpath(root, "trash"),
    }) do
        local accessible, err = vim.uv.fs_access(path, "RWX")
        if accessible then
            health.ok("Storage access: " .. path)
        else
            health.error("Storage access failed: " .. path .. ": " .. tostring(err))
        end
    end

    local items, err, diagnostics = require("sess.session").list()
    if err then
        health.error("Store read failed: " .. err)
        return
    end

    for _, diagnostic in ipairs(diagnostics) do
        health.error(diagnostic)
    end

    for _, item in ipairs(items) do
        local path, path_err = storage.get_session_path(item.id)
        local stat = path and vim.uv.fs_stat(path)
        if not stat or stat.type ~= "file" or vim.fn.filereadable(path) == 0 then
            health.error(
                "Missing/unreadable snapshot for "
                    .. item.metadata.name
                    .. ": "
                    .. (path or path_err)
            )
        end
    end

    if #diagnostics == 0 then
        health.ok(#items .. " valid metadata records")
    end

    health.info(
        "Snapshots execute trusted Vimscript. Atomic replacement is not a multi-file transaction or crash-durability guarantee."
    )
end

return M
