-- HTTP through curl (in every OS this plugin supports, Windows 10 and later included).
--
-- Secrets never reach a command line, where other users of the computer could read them in
-- the process list: curl reads its whole configuration (URL, headers with the token) from
-- stdin, and a body goes through a file in Neovim's private temporary folder, removed after.

local async = require("programavimas.async")

local M = {}

M.VERSION = "0.1.0"

---@class programavimas.HttpRequest
---@field method? string
---@field url string
---@field headers? table<string, string>
---@field body? string
---@field timeout? integer  Seconds (default 20)

---@class programavimas.HttpResponse
---@field status integer
---@field headers table<string, string>  Lower-case names; the last response's headers
---@field body string

---@param value string
local function quoted(value)
  return '"' .. value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r") .. '"'
end

---@param text string
---@return table<string, string>
local function parse_headers(text)
  local headers = {}
  for line in text:gmatch("[^\r\n]+") do
    if line:match("^HTTP/") then
      headers = {}
    else
      local name, value = line:match("^([^:]+):%s*(.-)%s*$")
      if name then headers[name:lower()] = value end
    end
  end
  return headers
end

---@param path string
local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return "" end
  local text = file:read("*a")
  file:close()
  return text or ""
end

---@param path string
---@param text string
local function write_private(path, text)
  local fd = assert(vim.uv.fs_open(path, "w", 384)) -- 0600
  assert(vim.uv.fs_write(fd, text))
  vim.uv.fs_close(fd)
end

local function user_agent()
  local v = vim.version()
  return ("programavimas.nvim/%s Neovim/%d.%d.%d"):format(M.VERSION, v.major, v.minor, v.patch)
end

--- Sends a request; `done(nil, err)` on a network failure (curl's exit code and message).
---@param request programavimas.HttpRequest
---@param done fun(response: programavimas.HttpResponse?, err: string?)
function M.send(request, done)
  local dir = vim.fn.tempname()
  assert(vim.uv.fs_mkdir(dir, 448)) -- 0700
  local header_file, body_file = dir .. "/headers", dir .. "/body"
  local config = {
    "url = " .. quoted(request.url),
    "request = " .. quoted(request.method or "GET"),
    "silent",
    "show-error",
    "max-time = " .. tostring(request.timeout or 20),
    "connect-timeout = 10",
    "dump-header = " .. quoted(header_file),
    "output = " .. quoted(body_file),
    'write-out = "%{http_code}"',
    "user-agent = " .. quoted(user_agent()),
  }
  for name, value in pairs(request.headers or {}) do
    table.insert(config, "header = " .. quoted(name .. ": " .. value))
  end
  local data_file
  if request.body then
    data_file = dir .. "/data"
    write_private(data_file, request.body)
    table.insert(config, "data-binary = " .. quoted("@" .. data_file))
  end
  local ok, err = pcall(
    vim.system,
    { "curl", "--config", "-" },
    { stdin = table.concat(config, "\n") .. "\n", text = true },
    function(result)
      local response
      if result.code == 0 then
        response = {
          status = tonumber(vim.trim(result.stdout or "")) or 0,
          headers = parse_headers(read_file(header_file)),
          body = read_file(body_file),
        }
      end
      for _, path in ipairs({ header_file, body_file, data_file }) do
        if path then vim.uv.fs_unlink(path) end
      end
      vim.uv.fs_rmdir(dir)
      local message = response == nil
          and ("curl %d: %s"):format(result.code, vim.trim(result.stderr or ""))
        or nil
      vim.schedule(function() done(response, message) end)
    end
  )
  if not ok then
    vim.uv.fs_unlink(data_file or "")
    vim.uv.fs_rmdir(dir)
    vim.schedule(function() done(nil, "curl: " .. tostring(err)) end)
  end
end

--- `send` inside a task.
---@param request programavimas.HttpRequest
---@return programavimas.HttpResponse?, string?
function M.request(request)
  return async.await(function(done) M.send(request, done) end)
end

--- `application/x-www-form-urlencoded`
---@param value string
function M.encode(value)
  return (value:gsub("[^%w%-%._~]", function(char) return ("%%%02X"):format(char:byte()) end))
end

---@param fields table<string, string>
function M.form(fields)
  local keys = vim.tbl_keys(fields)
  table.sort(keys)
  local parts = {}
  for _, key in ipairs(keys) do
    table.insert(parts, M.encode(key) .. "=" .. M.encode(fields[key]))
  end
  return table.concat(parts, "&")
end

---@param value string
function M.decode(value)
  return (value:gsub("%+", " "):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

---@param query string
---@return table<string, string>
function M.parse_query(query)
  local params = {}
  for pair in query:gmatch("[^&]+") do
    local key, value = pair:match("^([^=]*)=?(.*)$")
    if key and key ~= "" then params[M.decode(key)] = M.decode(value) end
  end
  return params
end

--- A JSON body, or nil when it is not JSON. JSON null becomes nil.
---@param body string
---@return any
function M.json(body)
  local ok, value = pcall(vim.json.decode, body, { luanil = { object = true, array = true } })
  return ok and value or nil
end

return M
