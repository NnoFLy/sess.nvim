local marks = require("sess.ui.marks")

return {
    goto_mark = marks.goto_mark,

    -- The user-facing entry point reports failures even when returns are ignored.
    setup = function(opts)
        local ok, err = require("sess.api").opts.setup(opts)
        if not ok then
            require("sess.log").error("Setup failed: " .. err)
        end

        return ok, err
    end,
}
