local M = {}

function M.job_id(bufnr)
    local ok, value = pcall(function() return vim.b[bufnr].terminal_job_id end)
    return ok and value or nil
end

function M.name(bufnr)
    local ok, value = pcall(vim.api.nvim_buf_get_name, bufnr)
    if not ok then return nil end
    return value:match("([^:]+)$")
end

function M.lines(bufnr)
    local ok, count = pcall(vim.api.nvim_buf_line_count, bufnr)
    if not ok then return nil end
    local lines_ok, lines = pcall(vim.api.nvim_buf_get_lines, bufnr, math.max(0, count - 200), count, false)
    if not lines_ok then return nil end

    local last = #lines
    while last > 0 and vim.trim(lines[last]) == "" do last = last - 1 end
    local result = {}
    for index = math.max(1, last - 24), last do
        local line = lines[index]:gsub("\r", "")
        line = line:gsub("\27%][^\7]*\7", "")
        line = line:gsub("\27%[[0-?]*[ -/]*[@-~]", "")
        result[#result + 1] = line
    end
    return result
end

return M
