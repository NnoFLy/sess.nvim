local M = {}

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local api = require("sess.api")
local log = require("sess.log")
local finders = require("telescope._extensions.sess.finders")

---@param prompt_bufnr number
---@return nil
local function refresh(prompt_bufnr)
    local current_picker = action_state.get_current_picker(prompt_bufnr)
    current_picker:refresh(finders.generate_new_finder(), { reset_prompt = true })
end

---@return Sess.TelescopeSessionEntry | nil
local function selected_value()
    local selected = action_state.get_selected_entry()
    if not selected then
        return nil
    end

    return selected.value
end

---@param prompt_bufnr number
---@return nil
function M.enter(prompt_bufnr)
    actions.close(prompt_bufnr)

    local value = selected_value()
    if not value then
        return
    end

    local ok, err
    if value.id == nil then
        ok, err = api.session.create(value.metadata.cwd)
    else
        ok, err = api.session.load(value.id)
    end

    if not ok then
        log.error(err)
    end
end

---@param prompt_bufnr number
---@return nil
function M.delete_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end

    local ok, err = api.session.delete(value.id)
    if not ok then
        log.error(err)
    end

    refresh(prompt_bufnr)
end

---@param prompt_bufnr number
---@return nil
function M.toggle_pin_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end

    local ok, err = api.session.toggle_pin(value.id)
    if not ok then
        log.error(err)
    end

    refresh(prompt_bufnr)
end

---@param prompt_bufnr number
---@return nil
function M.rename_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end

    vim.ui.input({
        prompt = "Enter Session Name: ",
        default = value.metadata.name,
    }, function(name)
        if not name then
            return
        end

        name = vim.trim(name)
        if name == "" then
            return
        end

        local ok, err = api.session.rename(value.id, name)
        if not ok then
            log.error(err)
        end

        refresh(prompt_bufnr)
    end)
end

return M
