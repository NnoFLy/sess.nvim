return {
    -- The user-facing entry point reports failures even when returns are ignored.
    setup = function(opts)
        local ok, err = require("sess.api").opts.setup(opts)
        if not ok then
            require("sess.log").error("Setup failed: " .. err)
        end

        return ok, err
    end,
}
