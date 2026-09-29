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

---@class Sess.DeletedSession
---@field key string
---@field id Sess.SessionId
---@field metadata Sess.SessionMetadata
---@field deleted_at Sess.Timestamp

---@class Sess.Operation
---@field operation "create"|"load"|"save"|"unload"|"delete"|"rename"|"pin"|"restore"
---@field session Sess.Session
---@field current Sess.Session? Current before a pre-hook, after a post-hook/event.

---@class Sess.Hooks
---@field before_transition fun(context: Sess.Operation)? May throw to prevent create/load/unload/restore/current-delete.
---@field after_operation fun(context: Sess.Operation)? Errors become diagnostics after success.

---@class Sess.OperationOpts
---@field hooks Sess.Hooks?

---@class Sess.UnloadBuffer
---@field buf integer
---@field name string
---@field modified boolean
---@field changedtick integer
---@field terminal boolean
---@field job integer? Live terminal job ID, if any.

---@class Sess.UnloadConfirmation
---@field kind "buffers"|"jobs"
---@field session Sess.Session
---@field buffers Sess.UnloadBuffer[] Only exclusive resources needing consent.

---Return save/discard for buffers, stop for jobs; anything else cancels.
---The optional second result supplies unnamed-buffer save paths.
---@class Sess.UnloadOpts: Sess.OperationOpts
---@field confirm? fun(request: Sess.UnloadConfirmation): string, table<integer, string>?

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
