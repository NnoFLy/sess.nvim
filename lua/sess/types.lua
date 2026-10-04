---@alias Sess.Version integer
---@alias Sess.Timestamp integer
---@alias Sess.SessionId string
---@alias Sess.Cwd string
---@alias Sess.log_level "debug" | "info" | "warn" | "error"
---@alias Sess.DBPath string

---@class Sess.SessionMetadata
---@field version Sess.Version
---@field name string
---@field cwd Sess.Cwd Absolute canonical project identity; snapshots retain the actual editor cwd scopes.
---@field created_at Sess.Timestamp
---@field last_used_at Sess.Timestamp
---@field pinned boolean

---@class Sess.Session
---@field id Sess.SessionId
---@field metadata Sess.SessionMetadata

---@alias Sess.Mark string One lowercase ASCII letter or digit.

---@class Sess.MarkEntry
---@field mark Sess.Mark
---@field id Sess.SessionId Owner, including a missing or deleted session.
---@field session Sess.Session?
---@field stale boolean
---@field error string?

---@class Sess.SetMarkOpts: Sess.OperationOpts
---@field replace boolean? Explicit permission to replace an existing owner.

---@class Sess.MoveMarkOpts: Sess.OperationOpts
---@field replace boolean? Explicit permission to replace an existing destination.

---@class Sess.AgentTarget
---@field bufnr integer Valid at registration time; may disappear later.
---@field winid integer? Last known window containing bufnr.

---@class Sess.Agent
---@field id string Session-local stable identifier.
---@field name string Short display name.
---@field info string? Optional display information.
---@field status string? Optional status: idle, working, blocked, done, unknown, or integration-defined.
---@field target Sess.AgentTarget

---@class Sess.DeletedSession
---@field key string
---@field id Sess.SessionId
---@field metadata Sess.SessionMetadata
---@field deleted_at Sess.Timestamp

---@class Sess.Preview
---@field session Sess.Session
---@field snapshot_status "available"|"invalid"|"unavailable"
---@field snapshot_available boolean
---@field snapshot_error string?

---@class Sess.Operation
---@field operation "create"|"load"|"save"|"unload"|"delete"|"rename"|"pin"|"restore"|"mark"|"unmark"
---@field session Sess.Session? Nil when clearing a stale mark.
---@field mark Sess.Mark? Mark/unmark operations only.
---@field session_id Sess.SessionId? Mark owner, even when stale.
---@field previous_id Sess.SessionId? Previous owner on mark replacement.
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

---@class Sess.Keymap
---@field prefix string
---@field set_mark string
---@field edit_marks string

---@class Sess.MarkWindowKeymap
---@field open string
---@field load_prefix string
---@field delete string
---@field undo string
---@field change_mark string
---@field rename string

---@class Sess.MarkWindowOptions
---@field position string
---@field width integer
---@field height integer
---@field margin integer
---@field border string
---@field title string
---@field title_pos "left"|"center"|"right"
---@field win_options { cursorline: boolean, winblend: integer, winhighlight: string }
---@field keymap Sess.MarkWindowKeymap

---@class Sess.Opts
---@field paths string[]
---@field log_level Sess.log_level
---@field smart_auto_load boolean
---@field auto_save boolean
---@field exclude_filetypes string[]
---@field hooks Sess.Hooks
---@field store_path Sess.DBPath
---@field keymap Sess.Keymap
---@field mark_window Sess.MarkWindowOptions
