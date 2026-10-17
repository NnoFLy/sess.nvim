fixture.setup()

local editor = require("sess.editor")
local normal = vim.api.nvim_get_current_buf()
vim.bo[normal].buflisted = true

vim.cmd("vsplit")
local transient_win = vim.api.nvim_get_current_win()
local transient_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(transient_win, transient_buf)
vim.b[transient_buf].sess_transient_ui = true
vim.bo[transient_buf].buflisted = true

assert(editor.is_transient_buffer(transient_buf))
assert(editor.is_transient_window(transient_win))
local view = editor.capture()
assert(not view.buffers[transient_buf])
assert(view.buffers[normal])
assert(not view.listing[transient_buf])
assert(#view.tabs == 1)
assert(not view.tabs[1].windows[transient_win])
local function contains_transient_leaf(node)
    if node[1] == "leaf" then return node[2] == transient_win end
    for _, child in ipairs(node[2] or {}) do
        if contains_transient_leaf(child) then return true end
    end
    return false
end
assert(not contains_transient_leaf(view.tabs[1].layout))
assert(view.tabs[1].current ~= transient_win)

-- A transient owner may mark only its window. Its private buffer must still
-- stay out of the session inventory while no normal window displays it.
vim.cmd("vsplit")
local window_owned_transient = vim.api.nvim_get_current_win()
local window_owned_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(window_owned_transient, window_owned_buf)
vim.w[window_owned_transient].sess_transient_ui = true
vim.bo[window_owned_buf].buflisted = true
local window_owned_view = editor.capture()
assert(not window_owned_view.buffers[window_owned_buf])
assert(not window_owned_view.listing[window_owned_buf])
assert(not window_owned_view.tabs[1].windows[window_owned_transient])

local bufhidden = vim.bo[transient_buf].bufhidden
assert(editor.protected(function() return true end))
assert(vim.bo[transient_buf].bufhidden == bufhidden)

local owner_events = {}
local registered, registration_err = editor.register_transient_owner({
    suspend = function() owner_events[#owner_events + 1] = "suspend" end,
    resume = function() owner_events[#owner_events + 1] = "resume" end,
})
assert(registered, registration_err)
assert(editor.protected(function() return true end))
assert(vim.deep_equal(owner_events, { "suspend", "resume" }))
assert(vim.api.nvim_win_is_valid(transient_win))

local nested = { operations = 0, suspend = 0, resume = 0 }
local nested_registered, nested_registration_err = editor.register_transient_owner({
    suspend = function()
        nested.suspend = nested.suspend + 1
        local nested_ok, nested_err = editor.protected(function()
            nested.operations = nested.operations + 1
            return true
        end)
        assert(nested_ok, nested_err)
    end,
    resume = function() nested.resume = nested.resume + 1 end,
})
assert(nested_registered, nested_registration_err)
assert(not editor.is_transient_ui_suspended())
local nested_ok, nested_err = editor.protected(function() return true end)
assert(nested_ok, nested_err)
assert(nested.operations == 1)
assert(nested.suspend == 1)
assert(nested.resume == 1)
assert(vim.deep_equal(owner_events, { "suspend", "resume", "suspend", "resume" }))
assert(not editor.is_transient_ui_suspended())

editor.hide()
assert(vim.api.nvim_win_is_valid(transient_win))
assert(vim.api.nvim_buf_is_valid(transient_buf))
assert(vim.bo[transient_buf].buflisted)
