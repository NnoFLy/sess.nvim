local M = {}

M.save = require("sessions.commands.save").save_session
M.pin = require("sessions.commands.pin").pin_session
M.load = require("sessions.commands.load").load_session
M.last = require("sessions.commands.last").open_last
M.create = require("sessions.commands.create").create_session
M.delete = require("sessions.commands.delete").delete_session
M.list = require("sessions.commands.list").open_telescope_sessionizer

return M
