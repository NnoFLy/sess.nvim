local window = require("sess.ui.window")
local options = window.defaults()

for position in pairs({
    left_top = true,
    center_top = true,
    right_top = true,
    left_center = true,
    center = true,
    right_center = true,
    left_bottom = true,
    center_bottom = true,
    right_bottom = true,
}) do
    options.position = position
    local geometry, err = window.geometry(options, { width = 80, height = 24 })
    assert(geometry, err)
    assert(geometry.col >= 0 and geometry.row >= 0)
    assert(geometry.col + geometry.width + 2 <= 80)
    assert(geometry.row + geometry.height + 2 <= 24)
end

options.width = 200
options.height = 200
options.margin = 20
local geometry, err = window.geometry(options, { width = 30, height = 12 })
assert(geometry, err)
assert(geometry.width == 28 and geometry.height == 10)
assert(geometry.col == 0 and geometry.row == 0)

options.border = "double"
geometry, err = window.geometry(options, { width = 2, height = 2 })
assert(not geometry and err:match("minimum content"))

assert(not window.validate({ win_options = { unknown = true } }))
assert(not window.validate({ title = "two\nlines" }))
