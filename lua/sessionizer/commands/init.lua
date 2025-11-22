local M = {}

M.save = require("sessionizer.commands.save")
M.pin = require("sessionizer.commands.pin")
M.load = require("sessionizer.commands.load")
M.last = require("sessionizer.commands.last")
M.create = require("sessionizer.commands.create")
M.delete = require("sessionizer.commands.delete")
M.list = require("sessionizer.commands.list")

return M
