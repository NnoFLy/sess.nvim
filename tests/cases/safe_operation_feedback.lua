fixture.setup()

local api = require("sess.api")
local _, _, first = api.session.create(fixture.directory("first"), { name = "first" })
local _, _, second = api.session.create(fixture.directory("second"), { name = "second" })
assert(first and second)

local selected = { value = first }
local picker = {
    finder = { results = { first, second } },
    refresh = function(self, finder, options)
        assert(options.reset_prompt == false)
        self.finder = finder
        self.refreshed = true
    end,
    set_selection = function(self, index)
        self.selection = index
    end,
}
package.loaded["telescope.actions"] = { close = function() end }
package.loaded["telescope.actions.state"] = {
    get_selected_entry = function()
        return selected
    end,
    get_current_picker = function()
        return picker
    end,
}
package.loaded["telescope.finders"] = {
    new_table = function(options)
        return options
    end,
}
package.loaded["telescope.config"] = {
    values = { generic_sorter = function() return {} end },
}

local actions = require("telescope._extensions.sess.actions")
local original_input = vim.ui.input
local input_calls = 0
local input_callback
vim.ui.input = function(_, callback)
    input_calls = input_calls + 1
    input_callback = callback
end

-- An outstanding prompt owns the action until its callback completes.
actions.rename_session(1)
actions.rename_session(1)
assert(input_calls == 1)
input_callback(nil)
assert(not picker._sess_action_pending)

actions.rename_session(1)
assert(input_calls == 2)
input_callback("renamed")
assert(picker.refreshed)
assert(picker.selection ~= nil)
local renamed_ok, renamed_err, renamed = api.session.get(first.id)
assert(renamed_ok, renamed_err)
fixture.equal("renamed", renamed.metadata.name)

vim.ui.input = original_input
