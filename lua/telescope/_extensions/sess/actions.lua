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
    local value = selected_value()
    if not value then
        return
    end

    actions.close(prompt_bufnr)

    local ok, err, _, diagnostics
    if value.id == nil then
        ok, err, _, diagnostics = api.session.create(value.metadata.cwd)
    else
        ok, err, _, diagnostics = api.session.load(value.id)
    end

    if not ok then
        log.error(err)
    else
        log.diagnostics(diagnostics)
    end
end

---@param prompt_bufnr number
---@return nil
function M.delete_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end

    if vim.fn.confirm("Delete session " .. value.metadata.name .. "?", "&Yes\n&No", 2) ~= 1 then
        return
    end

    local current = api.state.current()
    local deleting_current = current and current.id == value.id

    -- A current-session deletion replaces the layout, including picker windows.
    if deleting_current then
        actions.close(prompt_bufnr)
    end

    local ok, err, _, diagnostics = api.session.delete(value.id)
    if not ok then
        log.error(err)
    else
        log.diagnostics(diagnostics)
    end

    if not deleting_current then
        refresh(prompt_bufnr)
    end
end

---@param prompt_bufnr number
---@return nil
function M.unload_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end

    local current = api.state.current()
    local unloading_current = current and current.id == value.id

    -- Close before capturing the current session so picker windows aren't saved.
    if unloading_current then
        actions.close(prompt_bufnr)
    end

    local ok, err, _, diagnostics = require("sess.ui.unload")(value.id)
    if ok then
        log.diagnostics(diagnostics)
    elseif err == "unload cancelled" then
        log.info("Unload cancelled")
    else
        log.error(err)
    end

    if not unloading_current then
        refresh(prompt_bufnr)
    end
end

---@param prompt_bufnr number
---@return nil
function M.toggle_pin_session(prompt_bufnr)
    local value = selected_value()
    if not value or not value.id then
        return
    end

    local ok, err, _, diagnostics = api.session.toggle_pin(value.id)
    if not ok then
        log.error(err)
    else
        log.diagnostics(diagnostics)
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

        local ok, err, _, diagnostics = api.session.rename(value.id, name)
        if not ok then
            log.error(err)
        else
            log.diagnostics(diagnostics)
        end

        refresh(prompt_bufnr)
    end)
end

return M
