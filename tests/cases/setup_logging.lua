local sess = require("sess")
local opts = require("sess.api.opts")

local messages = {}
vim.notify = function(message, level)
    table.insert(messages, { message = message, level = level })
end

-- Normal config calls often ignore return values; failures must still be visible.
sess.setup({ after_load = {} })
fixture.equal({
    {
        message = "[sess.nvim] Setup failed: unknown option: after_load",
        level = vim.log.levels.ERROR,
    },
}, messages)
assert(not opts.is_setup())

local ok, err = sess.setup({ hooks = { after_operation = false } })
assert(not ok)
fixture.equal("hooks.after_operation must be a function", err)
fixture.equal("[sess.nvim] Setup failed: " .. err, messages[2].message)
fixture.equal(vim.log.levels.ERROR, messages[2].level)

ok, err = sess.setup({ store_path = false })
assert(not ok)
fixture.equal("[sess.nvim] Setup failed: " .. err, messages[3].message)
assert(not opts.is_setup())

-- Correcting the config succeeds without a notification.
fixture.setup()
fixture.equal(3, #messages)
assert(opts.is_setup())
ok, err = sess.setup({})
assert(not ok)
fixture.equal("[sess.nvim] Setup failed: " .. err, messages[4].message)

-- Low-level configuration API remains silent for programmatic callers.
local count = #messages
ok, err = opts.setup({})
assert(not ok and err)
fixture.equal(count, #messages)
