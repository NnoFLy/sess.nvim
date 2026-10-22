-- Defaults and validation are observed through the public configuration seam.
fixture.startup([[
check(function()
    local api = require("sess.api")
    assert(api.opts.get().smart_auto_load == "current")
    local ok, err = require("sess").setup({ smart_auto_load = false })
    assert(not ok and err:find("smart_auto_load", 1, true), tostring(err))
end)
]])

for _, value in ipairs({ "true", '""', '"invalid"', "0", "{}", "function() end" }) do
    fixture.startup(string.format(
        [[
check(function()
    local ok, err = require("sess").setup({ smart_auto_load = %s })
    assert(not ok and err:find("smart_auto_load", 1, true), tostring(err))
    assert(not require("sess.api").opts.is_setup())
end)
]],
        value
    ))
end

for _, case in ipairs({
    { "{}", "current" },
    { "nil", "current" },
    { "{ smart_auto_load = nil }", "current" },
    { '{ smart_auto_load = "none" }', "none" },
    { '{ smart_auto_load = "current" }', "current" },
    { '{ smart_auto_load = "all" }', "all" },
}) do
    fixture.startup(string.format(
        [[
-- Resume orchestration is supplied by the integration owner.
package.preload["sess.api.resume"] = function()
    return { exit = function() return true end }
end
check(function()
    local options = %s
    if options then options.store_path = vim.fn.getcwd() .. "/options-store" end
    assert(require("sess").setup(options))
    assert(require("sess.api").opts.get().smart_auto_load == %q)
end)
]],
        case[1],
        case[2]
    ))
end
