local api = require("sess.api")

local function buffer_list(buffers)
    local lines = {}
    for index, buffer in ipairs(buffers) do
        if index > 10 then
            table.insert(lines, ("... and %d more"):format(#buffers - 10))
            break
        end
        table.insert(lines, buffer.name ~= "" and buffer.name or ("[No Name] #" .. buffer.buf))
    end

    return table.concat(lines, "\n")
end

-- Shared by commands and Telescope. All choices are gathered before the core
-- writes files or closes resources, so cancelling either prompt aborts unload.
local function confirm(request)
    if request.kind == "jobs" then
        local choice = vim.fn.confirm(
            "Stop running terminal jobs (including shells) and unload "
                .. request.session.metadata.name
                .. "?\n"
                .. buffer_list(request.buffers),
            "&Stop\n&Cancel",
            2
        )

        return choice == 1 and "stop" or "cancel"
    end

    local choice = vim.fn.confirm(
        "Unsaved buffers in "
            .. request.session.metadata.name
            .. ":\n"
            .. buffer_list(request.buffers),
        "&Save\n&Discard\n&Cancel",
        3
    )
    if choice == 2 then
        return "discard"
    end
    if choice ~= 1 then
        return "cancel"
    end

    local paths = {}
    for _, buffer in ipairs(request.buffers) do
        if buffer.name == "" then
            local path = vim.fn.input({
                prompt = "Save buffer " .. buffer.buf .. " as: ",
                default = request.session.metadata.cwd .. "/",
                completion = "file",
            })
            if vim.trim(path) == "" then
                return "cancel"
            end
            paths[buffer.buf] = path
        end
    end

    return "save", paths
end

return function(target)
    return api.session.unload(target, { confirm = confirm })
end
