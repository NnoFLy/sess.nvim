fixture.setup()

local api = require("sess.api")
assert(api.session.create(fixture.directory("healthy"), { name = "healthy" }))
assert(require("sess.storage").create("broken"))

local warnings = {}
vim.notify = function(message)
    table.insert(warnings, message)
end

require("sess.ui.command").setup()

local names = vim.fn.getcompletion("Sess load ", "cmdline")
assert(vim.list_contains(names, "healthy"))
assert(#warnings > 0 and warnings[1]:match("broken"))

-- Test the adapter contract without installing Telescope or its dependencies.
package.loaded["telescope.finders"] = {
    new_table = function(options)
        return options
    end,
}

local before = #warnings
local finder = require("telescope._extensions.sess.finders").generate_new_finder()
fixture.equal(1, #finder.results)
assert(#warnings > before and warnings[#warnings]:match("broken"))
