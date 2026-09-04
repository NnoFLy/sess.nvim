---@alias Sess.Version integer
---@alias Sess.Timestamp integer
---@alias Sess.SessionId string
---@alias Sess.Cwd string

---@alias Sess.log_level "debug" | "info" | "warn" | "error"
---@alias Sess.DBPath string


---@class Sess.SessionMetadata
---@field version Sess.Version
---@field name string
---@field cwd Sess.Cwd
---@field created_at Sess.Timestamp
---@field last_used_at Sess.Timestamp
---@field pinned boolean

---@class Sess.CreateOpts
---@field name string?
---@field cwd string?
---@field id Sess.SessionId?
---
---@class Sess.BeforeLoadOpts
---@field auto_save_files boolean
---@field auto_hide_buffers boolean
---@field custom function

---@class Sess.AfterLoadOpts
---@field custom function

---@class Sess.OnUnloadOpts
---@field custom function

---@class Sess.MergedLoadOpts
---@field before_load Sess.BeforeLoadOpts?
---@field after_load Sess.AfterLoadOpts?

---@class Sess.MergedUnloadOpts
---@field on_unload Sess.OnUnloadOpts?

---@class Sess.Session
---@field id Sess.SessionId
---@field metadata Sess.SessionMetadata

---
