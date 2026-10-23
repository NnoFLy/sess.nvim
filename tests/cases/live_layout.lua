fixture.setup()

local api = require("sess.api")
local editor = require("sess.editor")

vim.o.cmdheight = 0
vim.o.laststatus = 3
vim.o.showtabline = 1

local function layout_sizes(node, windows)
    if node[1] == "leaf" then
        local saved = windows[node[2]]
        return { "leaf", saved.buf, saved.width, saved.height }
    end

    local children = {}
    for _, child in ipairs(node[2]) do
        children[#children + 1] = layout_sizes(child, windows)
    end
    return { node[1], children }
end

-- Compare geometry and buffer identities without depending on recreated IDs.
local function geometry()
    local tabs = {}
    for _, tab in ipairs(editor.capture().tabs) do
        local floats = {}
        for _, float in ipairs(tab.floats) do
            local anchor = tab.windows[float.config.win]
            floats[#floats + 1] = {
                buf = float.saved.buf,
                width = float.config.width,
                height = float.config.height,
                relative = float.config.relative,
                anchor = anchor and anchor.buf,
            }
        end
        tabs[#tabs + 1] = { layout = layout_sizes(tab.layout, tab.windows), floats = floats }
    end
    return tabs
end

local ok, err, multi = api.session.create(fixture.directory("multi"))
assert(ok, err)
vim.cmd("tabnew")
vim.cmd("tabfirst")
local selected_buffer = vim.api.nvim_get_current_buf()
local expected = geometry()

local single
ok, err, single = api.session.create(fixture.directory("single"))
assert(ok, err)

local function switch_repeatedly()
    for _ = 1, 5 do
        local loaded, load_err = api.session.load(multi)
        assert(loaded, load_err)
        fixture.equal(selected_buffer, vim.api.nvim_get_current_buf())
        fixture.equal(1, vim.api.nvim_tabpage_get_number(0))
        fixture.equal(expected, geometry())

        -- cmdheight is tab-local: checking only the last tab misses growth in
        -- the first tab when tabonly/tabnew temporarily hide the tabline.
        local selected_tab = vim.api.nvim_get_current_tabpage()
        for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
            vim.api.nvim_set_current_tabpage(tab)
            fixture.equal(0, vim.o.cmdheight)
        end
        vim.api.nvim_set_current_tabpage(selected_tab)
        fixture.equal(1, vim.o.showtabline)

        loaded, load_err = api.session.load(single)
        assert(loaded, load_err)
        fixture.equal(1, #vim.api.nvim_list_tabpages())
        fixture.equal(0, vim.o.cmdheight)
    end
end

-- A single window in the first tab exposes the extra command-line row.
switch_repeatedly()

-- Delaying dimensions must also preserve unequal splits and window-relative
-- floats; float IDs must not enter the normal-window sizing pass.
assert(api.session.load(multi))
vim.cmd("split")
vim.cmd("resize 5")
vim.cmd("vsplit")
local anchor = vim.api.nvim_get_current_win()
local floating = vim.api.nvim_create_buf(false, true)
vim.api.nvim_open_win(floating, false, {
    relative = "win",
    win = anchor,
    row = 1,
    col = 1,
    width = 8,
    height = 2,
})
selected_buffer = vim.api.nvim_get_current_buf()
expected = geometry()
assert(api.session.load(single))
switch_repeatedly()
