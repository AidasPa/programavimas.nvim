-- The signed-in session per server: a short-lived access token and a rotating refresh token in
-- `stdpath("data")/programavimas/sessions.json`, readable only by the user (0600 in a 0700
-- folder), written atomically. Tokens go only to the server they were issued by and are never
-- shown or logged.
--
-- Several Neovims may share one session. A refresh token is single-use (rotation, with theft
-- detection on reuse), so refreshing takes a lock file and first re-reads the session, which
-- another Neovim may have refreshed already.

local async = require("programavimas.async")
local oauth = require("programavimas.oauth")

local M = {}

local EARLY_MS = 60 * 1000
local LOCK_STALE_S = 30

---@class programavimas.Session
---@field accessToken string
---@field accessExpiresAt number  Milliseconds since the epoch
---@field refreshToken string?
---@field scopes string[]
---@field accountId string
---@field accountName string

function M.dir()
  return vim.fs.joinpath(vim.fn.stdpath("data") --[[@as string]], "programavimas")
end

local function sessions_file() return vim.fs.joinpath(M.dir(), "sessions.json") end
local function lock_file() return vim.fs.joinpath(M.dir(), "sessions.lock") end

local function ensure_dir()
  vim.fn.mkdir(M.dir(), "p", tonumber("700", 8))
end

--- Reads a JSON file of ours; an empty table when missing or unreadable.
---@param path string
---@return table
function M.read_json(path)
  local file = io.open(path, "r")
  if not file then return {} end
  local text = file:read("*a")
  file:close()
  local ok, value = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  return ok and type(value) == "table" and value or {}
end

--- Writes a JSON file of ours atomically, readable only by the user.
---@param path string
---@param value table
function M.write_json(path, value)
  ensure_dir()
  local tmp = path .. ".tmp" .. tostring(vim.uv.os_getpid())
  local fd = assert(vim.uv.fs_open(tmp, "w", tonumber("600", 8)))
  assert(vim.uv.fs_write(fd, vim.json.encode(value)))
  vim.uv.fs_close(fd)
  assert(vim.uv.fs_rename(tmp, path))
end

---@param origin string
---@return programavimas.Session?
function M.get(origin)
  local value = M.read_json(sessions_file())[origin]
  if type(value) ~= "table" or type(value.accessToken) ~= "string" then return nil end
  return value
end

---@param origin string
---@param session programavimas.Session?
function M.set(origin, session)
  local all = M.read_json(sessions_file())
  all[origin] = session
  M.write_json(sessions_file(), all)
end

---@param tokens programavimas.Tokens
---@param account { id: string, name: string }
---@param previous programavimas.Session?
---@return programavimas.Session
function M.from_tokens(tokens, account, previous)
  local now = os.time() * 1000
  return {
    accessToken = tokens.access_token,
    accessExpiresAt = now + (tonumber(tokens.expires_in) or 300) * 1000,
    -- A refresh response without a new refresh token keeps the old one (RFC 6749 §6).
    refreshToken = tokens.refresh_token or (previous and previous.refreshToken) or nil,
    scopes = vim.split(tokens.scope or table.concat(oauth.SCOPES, " "), " ", { trimempty = true }),
    accountId = account.id,
    accountName = account.name,
  }
end

---@param session programavimas.Session
---@param stale string?  An access token the server refused, which must not be returned again
local function usable(session, stale)
  return session.accessToken ~= stale and session.accessExpiresAt - os.time() * 1000 > EARLY_MS
end

--- Takes the refresh lock (another Neovim's lock older than 30 s is abandoned).
local function lock()
  ensure_dir()
  for _ = 1, 50 do
    local fd = vim.uv.fs_open(lock_file(), "wx", tonumber("600", 8))
    if fd then
      vim.uv.fs_close(fd)
      return true
    end
    local stat = vim.uv.fs_stat(lock_file())
    if stat and os.time() - stat.mtime.sec > LOCK_STALE_S then vim.uv.fs_unlink(lock_file()) end
    async.sleep(200)
  end
  return false
end

local function unlock() vim.uv.fs_unlink(lock_file()) end

--- A usable access token for `origin`, refreshed when it is about to expire or was refused.
---@param origin string
---@param meta_of fun(): table?, table?  The server's OAuth metadata (discovered once)
---@param stale string?  The access token the server just refused
---@return string? token, "signed_out"|"expired"|"network"|nil reason
function M.access_token(origin, meta_of, stale)
  local session = M.get(origin)
  if not session then return nil, "signed_out" end
  if usable(session, stale) then return session.accessToken, nil end
  if not session.refreshToken then return nil, "expired" end
  if not lock() then return nil, "network" end
  local ok, token, reason = pcall(function()
    -- Another Neovim may have refreshed while this one waited.
    session = M.get(origin)
    if not session then return nil, "signed_out" end
    if session.accessToken ~= stale and session.accessExpiresAt > os.time() * 1000 then
      return session.accessToken, nil
    end
    local meta = meta_of()
    if not meta then return nil, "network" end
    local tokens, err = oauth.refresh(meta, session.refreshToken)
    if not tokens then
      if err and err.kind == "invalid_grant" then
        M.set(origin, nil)
        return nil, "expired"
      end
      return nil, err and err.kind == "network" and "network" or "expired"
    end
    local next_session = M.from_tokens(tokens, { id = session.accountId, name = session.accountName }, session)
    M.set(origin, next_session)
    return next_session.accessToken, nil
  end)
  unlock()
  if not ok then error(token) end
  return token, reason
end

return M
