---@alias Sess.Version integer
---@alias Sess.Timestamp integer
---@alias Sess.SessionId string
---@alias Sess.Cwd string
---@alias Sess.log_level "debug" | "info" | "warn" | "error"
---@alias Sess.DBPath string

---@class Sess.SessionMetadata
---@field version Sess.Version
---@field name string
---@field cwd Sess.Cwd Project identity; snapshots retain the actual editor cwd scopes.
---@field created_at Sess.Timestamp
---@field last_used_at Sess.Timestamp
---@field pinned boolean

---@class Sess.Session
---@field id Sess.SessionId
---@field metadata Sess.SessionMetadata

---@class Sess.Operation
---@field operation "create"|"load"|"save"|"unload"|"delete"|"rename"|"pin"
---@field session Sess.Session
---@field current Sess.Session? Current before a pre-hook, after a post-hook/event.

---@class Sess.Hooks
---@field before_transition fun(context: Sess.Operation)? May throw to prevent create/load/unload/current-delete.
---@field after_operation fun(context: Sess.Operation)? Errors become diagnostics after success.

---@class Sess.OperationOpts
---@field hooks Sess.Hooks?

---@class Sess.CreateOpts: Sess.OperationOpts
---@field name string?
---@field cwd string? Internal catalog only; public create accepts cwd as its first argument.
---@field id Sess.SessionId?

---@class Sess.Opts
---@field paths string[]
---@field log_level Sess.log_level
---@field smart_auto_load boolean
---@field auto_save boolean
---@field exclude_filetypes string[]
---@field hooks Sess.Hooks
---@field store_path Sess.DBPath
