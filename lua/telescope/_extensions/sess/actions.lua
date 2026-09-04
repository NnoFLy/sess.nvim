local M = {}

local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

local commands = require("sess.commands")
local log = require("sess.log")
local consts = require("sess.consts")
local finders = require("telescope._extensions.sess.finders")

---@param telescope_entry Sess.TelescopSessionEntry
---@return Sess.Session
local function to_session(telescope_entry)
    return {
        id = telescope_entry.id,
        metadata = {
            version = consts.get_version(),
            name = telescope_entry.metadata.name,
            cwd = telescope_entry.metadata.cwd,
            created_at = telescope_entry.metadata.created_at,
            last_used_at = telescope_entry.metadata.last_used_at,
            pinned = telescope_entry.metadata.pinned,
        }
    }
end

---@param prompt_bufnr number
---@return nil
local function refresh(prompt_bufnr)
    local current_picker = action_state.get_current_picker(prompt_bufnr)
    current_picker:refresh(finders.generate_new_finder(), { reset_prompt = true })
end

---@param prompt_bufnr number
---@return nil
function M.enter(prompt_bufnr)
    actions.close(prompt_bufnr)

    ---@type Sess.TelescopFinderReturn
    local selected = action_state.get_selected_entry()
    if not selected then
        return
    end

    local value = selected.value
    if value.id == nil then
        commands.create(value.metadata.cwd)
        return
    end

    local ok, err = commands.load(to_session(value))
    if not ok then
        log.error(err)
    end
end

---@param prompt_bufnr number
---@return nil
function M.delete_session(prompt_bufnr)
    ---@type Sess.TelescopFinderReturn
    local selected = action_state.get_selected_entry()
    if not selected or not selected.value.id then
        return
    end

    local ok, err = commands.delete(to_session(selected.value))
    if not ok then
        log.error(err)
    end

    refresh(prompt_bufnr)
end

---@param prompt_bufnr number
---@return nil
function M.toggle_pin_session(prompt_bufnr)
    ---@type Sess.TelescopFinderReturn
    local selected = action_state.get_selected_entry()
    if not selected then
        return
    end

    local ok, err = commands.pin(to_session(selected.value))
    if not ok then
        log.error(err)
    end

    refresh(prompt_bufnr)
end

---@param prompt_bufnr number
---@return nil
function M.rename_session(prompt_bufnr)
    ---@type Sess.TelescopFinderReturn
    local selected = action_state.get_selected_entry()
    if not selected then
        return
    end

    local ok, err = commands.rename(to_session(selected.value))
    if not ok then
        log.error(err)
    end

    refresh(prompt_bufnr)
end

return M
