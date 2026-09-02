local M = {}

M.save = require("sess.commands.save")
M.pin = require("sess.commands.pin")
M.load = require("sess.commands.load")
M.unload = require("sess.commands.unload")
M.last = require("sess.commands.last")
M.create = require("sess.commands.create")
M.rename = require("sess.commands.rename")
M.delete = require("sess.commands.delete")
M.list = require("sess.commands.list")

return M
