---@alias Sess.Version integer
---@alias Sess.Timestamp integer
---@alias Sess.SessionId string
---@alias Sess.Cwd string

---@class Sess.SessionMetadata
---@field version Sess.Version
---@field name string
---@field cwd Sess.Cwd
---@field created_at Sess.Timestamp
---@field last_used_at Sess.Timestamp
---@field pinned boolean

---@class Sess.IndexEntry
---@field name string
---@field cwd Sess.Cwd
---@field last_used_at Sess.Timestamp
---@field pinned boolean

---@class Sess.CreateOpts
---@field name string?
---@field cwd string?
---@field id Sess.SessionId?

---@class Sess.Session
---@field id Sess.SessionId
---@field metadata Sess.SessionMetadata
