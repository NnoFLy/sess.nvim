---@class Session
---@field name string | nil
---@field path string | nil

local M = {}

M.get_current = require("sessions.commands.get_current").get_current
M.open_list = require("sessions.commands.list").open_list
M.save_session = require("sessions.commands.save").save_session
M.pin_session = require("sessions.commands.pin").pin_session
M.attach_session = require("sessions.commands.attach").attach_session
M.open_last = require("sessions.commands.last").open_last
M.delete_session = require("sessions.commands.delete").delete_session
M.rename_session = require("sessions.commands.rename").rename_session

return M
