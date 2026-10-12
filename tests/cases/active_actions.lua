fixture.setup()

package.loaded["telescope.actions"] = {
    close = function() end,
}
local selected
local picker = {
    _sess_help_kind = "active",
    _sess_action_pending = false,
}
local action_state = {
    get_selected_entry = function()
        return selected
    end,
    get_current_picker = function()
        return picker
    end,
}
package.loaded["telescope.actions.state"] = action_state
package.loaded["telescope.finders"] = {
    new_table = function(value)
        return value
    end,
}
package.loaded["telescope.config"] = {
    values = { generic_sorter = function() end },
}
package.loaded["telescope.previewers"] = {
    new_buffer_previewer = function(options)
        return options
    end,
}

local api = require("sess.api")
local actions = require("telescope._extensions.sess.actions")
local session_id = "active-session"
local active_value = {
    kind = "session",
    session_id = session_id,
    session = {
        id = session_id,
        metadata = { name = "active", cwd = "/tmp/active" },
    },
}
selected = { value = active_value }

local refresh_count = 0
local original_refresh_active = actions.refresh_active
actions.refresh_active = function()
    refresh_count = refresh_count + 1
end

local original_toggle_pin = api.session.toggle_pin
local toggled_id
api.session.toggle_pin = function(id)
    toggled_id = id
    return true, nil, nil, {}
end
actions.toggle_pin_session(1)
assert(toggled_id == session_id)
assert(refresh_count == 1)

local original_delete = api.session.delete
local deleted_id
api.session.delete = function(id)
    deleted_id = id
    return true, nil, nil, {}
end
local original_confirm = vim.fn.confirm
vim.fn.confirm = function()
    return 1
end
actions.delete_session(1)
assert(deleted_id == session_id)
assert(refresh_count == 2)

local original_unload = package.loaded["sess.ui.unload"]
local unloaded_id
package.loaded["sess.ui.unload"] = function(id)
    unloaded_id = id
    return true, nil, nil, {}
end
actions.unload_session(1)
assert(unloaded_id == session_id)
assert(refresh_count == 3)

local original_rename = api.session.rename
local renamed_id
local renamed_name
api.session.rename = function(id, name)
    renamed_id = id
    renamed_name = name
    return true, nil, nil, {}
end
local original_input = vim.ui.input
vim.ui.input = function(_, callback)
    callback("renamed")
end
actions.rename_session(1)
assert(renamed_id == session_id)
assert(renamed_name == "renamed")
assert(refresh_count == 4)

local original_list_marks = api.session.list_marks
local original_clear_mark = api.session.clear_mark
local cleared_mark
api.session.list_marks = function()
    return true, nil, { { id = session_id, mark = "a" } }, {}
end
api.session.clear_mark = function(mark)
    cleared_mark = mark
    return true, nil, nil, {}
end
actions.unmark_session(1)
assert(cleared_mark == "a")
assert(refresh_count == 5)

api.session.toggle_pin = original_toggle_pin
api.session.delete = original_delete
api.session.rename = original_rename
api.session.list_marks = original_list_marks
api.session.clear_mark = original_clear_mark
package.loaded["sess.ui.unload"] = original_unload
vim.fn.confirm = original_confirm
vim.ui.input = original_input
actions.refresh_active = original_refresh_active
