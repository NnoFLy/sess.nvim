local setup = [[
local root = vim.env.SESS_TEST_ROOT
assert(require("sess").setup({ store_path = root .. "/store", smart_auto_load = "none",
    auto_save = false, tabline = { enabled = false } }))
local api = require("sess.api")
]]
local function after(code)
    return [[
vim.api.nvim_create_autocmd("VimEnter", { callback = function() vim.defer_fn(function() check(function()
]] .. code .. [[
end) end, 30) end })
]]
end
fixture.startup(setup .. after([[
for _, id in ipairs({ "a", "b", "c" }) do
    local dir = root .. "/" .. id
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile({ "context " .. id }, dir .. "/file.txt")
    assert(api.session.create(dir, { id = id }))
    vim.cmd.edit(dir .. "/file.txt")
    assert(api.session.save())
end
]]))
local path = fixture.root .. "/store/resume.json"
local function publish(ids, current)
    vim.fn.writefile(
        { vim.json.encode({ version = 1, active_ids = ids, current_id = current }) },
        path
    )
end
local function resume(before, assertion)
    return fixture.startup(
        setup:gsub('smart_auto_load = "none"', 'smart_auto_load = "all"')
            .. (before or "")
            .. after(assertion)
    )
end
local function assert_order(ids, current)
    return string.format(
        [[
assert(vim.deep_equal(%s, vim.tbl_map(function(s) return s.id end, api.state.active())))
assert(api.state.current().id == %q)
assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == %q)
]],
        vim.inspect(ids),
        current,
        "context " .. current
    )
end
-- Selection loaded last must not reorder active membership, even if first recorded.
publish({ "a", "b", "c" }, "a")
resume(nil, assert_order({ "a", "b", "c" }, "a"))
-- Missing current: skip it, select first survivor deterministically, no creation.
publish({ "a", "missing", "b" }, "missing")
local skipped = resume(nil, assert_order({ "a", "b" }, "a"))
assert(skipped.stderr:find("cannot resume missing", 1, true))

-- Empty, absent, wholly unusable, corrupt, incompatible and unsafe history never
-- falls back to cwd loading and is not repaired by a never-managed exit.
for _, document in ipairs({
    false,
    '{"version":1,"active_ids":[]}',
    '{"version":1,"active_ids":["missing"]}',
    '{"version":99,"active_ids":[]}',
    '{"version":1,"active_ids":["../escape"]}',
    '{"version":1,"active_ids":[],"snapshot":"evil.vim"}',
    "not JSON",
}) do
    vim.fn.delete(path)
    if document then
        vim.fn.writefile({ document }, path)
    end
    local output = resume(
        nil,
        [[
assert(api.state.current() == nil)
assert(#api.state.active() == 0)
assert(vim.api.nvim_buf_get_name(0) == "")
assert(vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "")
assert(#select(3, api.session.list()) == 3)
]]
    )
    if document then
        fixture.equal({ document }, vim.fn.readfile(path))
        if document ~= '{"version":1,"active_ids":[]}' then
            assert(output.stderr:find("[sess.nvim]", 1, true), output.stderr)
        end
    else
        assert(vim.fn.filereadable(path) == 0)
    end
end

-- Preflight skips invalid metadata, missing cwd and unavailable snapshots.
local metadata = fixture.root .. "/store/sessions/b/metadata.json"
local old_metadata = vim.fn.readfile(metadata)
vim.fn.writefile({ "broken" }, metadata)
publish({ "a", "b", "c" }, "b")
local broken = resume(nil, assert_order({ "a", "c" }, "a"))
assert(broken.stderr:find("cannot resume b", 1, true))
fixture.equal({ "broken" }, vim.fn.readfile(metadata))
vim.fn.writefile(old_metadata, metadata)
assert(vim.uv.fs_rename(fixture.root .. "/b", fixture.root .. "/b-away"))
publish({ "a", "b", "c" }, "b")
local missing_cwd = resume(nil, assert_order({ "a", "c" }, "a"))
assert(missing_cwd.stderr:find("directory does not exist", 1, true))
assert(vim.uv.fs_rename(fixture.root .. "/b-away", fixture.root .. "/b"))
assert(vim.uv.fs_unlink(fixture.root .. "/store/sessions/b/session.vim"))
publish({ "a", "b", "c" }, "b")
local missing_snapshot = resume(nil, assert_order({ "a", "c" }, "a"))
assert(missing_snapshot.stderr:find("cannot resume b", 1, true))

-- Structurally corrupt snapshots are diagnosed in preflight, never sourced.
vim.fn.writefile(
    { "let g:corrupt_snapshot_was_sourced = 1" },
    fixture.root .. "/store/sessions/b/session.vim"
)
publish({ "a", "b", "c" }, "b")
local corrupt_snapshot = resume(nil, assert_order({ "a", "c" }, "a") .. [[
assert(vim.g.corrupt_snapshot_was_sourced == nil)
]])
assert(corrupt_snapshot.stderr:find("cannot resume b", 1, true))

-- Unsafe resume paths and snapshot symlinks never source outside the store.
local outside = fixture.root .. "/outside.json"
vim.fn.writefile({ '{"version":1,"active_ids":["a"],"current_id":"a"}' }, outside)
assert(vim.uv.fs_unlink(path))
assert(vim.uv.fs_symlink(outside, path))
local unsafe = resume(nil, [[assert(api.state.current() == nil)]])
assert(unsafe.stderr:find("untrusted resume record", 1, true))
assert(vim.uv.fs_lstat(path).type == "link")
assert(vim.uv.fs_unlink(path))
local snapshot_path = fixture.root .. "/store/sessions/b/session.vim"
assert(vim.uv.fs_unlink(snapshot_path))
local outside_snapshot = fixture.root .. "/outside.vim"
vim.fn.writefile(
    { "let SessionLoad = 1", "let g:outside_sourced = 1", "unlet SessionLoad" },
    outside_snapshot
)
assert(vim.uv.fs_symlink(outside_snapshot, snapshot_path))
publish({ "a", "b", "c" }, "b")
local unsafe_snapshot =
    resume(nil, assert_order({ "a", "c" }, "a") .. [[assert(vim.g.outside_sourced == nil)]])
assert(unsafe_snapshot.stderr:find("cannot resume b", 1, true))
assert(vim.uv.fs_lstat(snapshot_path).type == "link")
