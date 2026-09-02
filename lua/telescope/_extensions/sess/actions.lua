local M = {}

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local commands = require("sess.commands")
local log = require("sess.log")

---@param prompt_bufnr number
---@return nil
function M.enter(prompt_bufnr)
    actions.close(prompt_bufnr)

    local selected = action_state.get_selected_entry()
    if not selected then
        return
    end

    local value = selected.value
    if value.metadata == nil then
        commands.create(value.path)
        return
    end

    commands.load(value)
end

---@param prompt_bufnr number
---@return nil
function M.delete_session(prompt_bufnr)
    actions.close(prompt_bufnr)

    local selected = action_state.get_selected_entry()
    if not selected or not selected.value.metadata then
        return
    end

    if not commands.delete(selected.value) then
        log.error("Failed to delete session")
    end

    commands.list()
end

---@param prompt_bufnr number
---@return nil
function M.rename_session(prompt_bufnr)
    actions.close(prompt_bufnr)

    local selected = action_state.get_selected_entry()
    if not selected or not selected.value.metadata then
        return
    end

    commands.rename(selected.value)
    commands.list()
end

return M
