fixture.setup()

local api = require("sess.api")
local detector = require("sess.agent.detect")
local _, _, session = api.session.create(fixture.directory("project"))

local terminal = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(0, terminal)
vim.api.nvim_open_term(terminal, {})
vim.b[terminal].terminal_job_id = 77

assert(detector.identify("/opt/bin/codex-cli") == "codex")
assert(detector.identify("/opt/bin/opencode-cli") == "opencode")

local original_jobpid = vim.fn.jobpid
local original_readfile = vim.fn.readfile
local files = {
    ["/proc/1001/cmdline"] = { "/usr/bin/env\0AGENT=1\0/opt/bin/codex-cli\0" },
    ["/proc/1001/task/1001/children"] = {},
}
vim.fn.jobpid = function()
    return 1001
end
vim.fn.readfile = function(path, mode)
    if files[path] then
        return files[path]
    end
    return original_readfile(path, mode)
end

local ok, err, agents = api.agent.list(session.id)
assert(ok, err)
assert(#agents == 1 and agents[1].name == "codex", vim.inspect(agents))

-- A shell process can outlive the agent command while the agent remains its
-- child. Discovery must inspect the process tree rather than only argv[0].
files["/proc/1001/cmdline"] = { "/bin/sh\0-c\0wait\0" }
files["/proc/1001/task/1001/children"] = { "1002" }
files["/proc/1002/cmdline"] = { "/usr/sbin/opencode\0" }
files["/proc/1002/task/1002/children"] = {}

ok, err, agents = api.agent.list(session.id)
assert(ok, err)
assert(#agents == 1 and agents[1].name == "opencode", vim.inspect(agents))

vim.fn.jobpid = original_jobpid
vim.fn.readfile = original_readfile
