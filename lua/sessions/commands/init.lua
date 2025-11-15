---@class Session
---@field name string | nil
---@field path string | nil

local M = {}

M.get = require("sessions.commands.get")
M.list = require("sessions.commands.list").open_list
M.save = require("sessions.commands.save").save_session
M.pin = require("sessions.commands.pin").pin_session
M.load = require("sessions.commands.load").load_session
M.last = require("sessions.commands.last").open_last
M.delete = require("sessions.commands.delete").delete_session
M.rename = require("sessions.commands.rename").rename_session

return M
