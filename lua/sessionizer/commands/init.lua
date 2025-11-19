local M = {}

M.save = require("sessionizer.commands.save").save_session
M.pin = require("sessionizer.commands.pin").pin_session
M.load = require("sessionizer.commands.load").load_session
M.last = require("sessionizer.commands.last").open_last
M.create = require("sessionizer.commands.create").create_session
M.delete = require("sessionizer.commands.delete").delete_session
M.list = require("sessionizer.commands.list").open_telescope_sessionizer

return M
