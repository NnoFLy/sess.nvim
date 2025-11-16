local M = {}

M.list = require("sessions.commands.list").open_list
M.save = require("sessions.commands.save").save_session
M.pin = require("sessions.commands.pin").pin_session
M.load = require("sessions.commands.load").load_session
M.last = require("sessions.commands.last").open_last
M.delete = require("sessions.commands.delete").delete_session

return M
