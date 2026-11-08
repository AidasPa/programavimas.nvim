-- Settings: `require("programavimas").setup(opts)` merges `opts` over these defaults.

local M = {}

---@class programavimas.Keymaps
---@field run string|false        Run the samples
---@field custom string|false     Run with the custom input file
---@field submit string|false     Submit (uses an attempt)
---@field statement string|false  Show the statement
---@field results string|false    Show or hide the results
---@field language string|false   Switch the solution's language

---@class programavimas.Config
---@field server string            The server (its APP_URL); https, or http for localhost only
---@field solutions_dir string?    Where solution folders live; nil asks on first open
---@field language "account"|"lt"|"en"
---@field keymaps programavimas.Keymaps|false  Buffer-local keys in solution files
---@field save_before_run boolean  Write a modified solution buffer before running or submitting
---@field icons table<string,string>
---@field courses { width: integer, position: "left"|"right" }
---@field results { height: integer }
M.defaults = {
  server = "https://beta.programavimas.xyz",
  solutions_dir = nil,
  language = "account",
  keymaps = {
    run = "<localleader>r",
    custom = "<localleader>i",
    submit = "<localleader>s",
    statement = "<localleader>p",
    results = "<localleader>t",
    language = "<localleader>l",
  },
  save_before_run = true,
  -- Plain Unicode by default (no Nerd Font needed); override any of them.
  icons = {
    not_started = "○",
    attempted = "◑",
    complete = "✓",
    locked = "◌",
    accepted = "✓",
    failed = "✗",
    limit = "◷",
    output = "≡",
    compile = "✗",
    system = "⊘",
    expanded = "▾",
    collapsed = "▸",
    difficulty = "▂▄▆",
    synced = "☁",
    syncing = "↑",
  },
  courses = { width = 42, position = "left" },
  results = { height = 14 },
}

---@type programavimas.Config
M.options = vim.deepcopy(M.defaults)

---@param opts table?
function M.setup(opts)
  if opts ~= nil and type(opts) ~= "table" then error("programavimas.setup: opts must be a table") end
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  if opts and opts.keymaps == false then M.options.keymaps = false end
end

--- The server's origin (scheme, host and port), or nil when the setting is not one the access
--- token may go to: https anywhere, plain http only on this computer.
---@param value string?
---@return string?
function M.origin_of(value)
  if type(value) ~= "string" then return nil end
  local scheme, authority = value:match("^(https?)://([^/?#]+)")
  if not scheme or authority:find("@", 1, true) then return nil end
  authority = authority:lower()
  local host = authority:match("^%[[^%]]+%]") or authority:match("^[^:]+")
  local port = authority:sub(#host + 1)
  if port ~= "" and not port:match("^:%d+$") then return nil end
  if (scheme == "https" and port == ":443") or (scheme == "http" and port == ":80") then
    port = ""
  end
  local loopback = host == "localhost" or host == "127.0.0.1" or host == "[::1]"
  if scheme == "http" and not loopback then return nil end
  return scheme .. "://" .. host .. port
end

---@return string?
function M.origin()
  return M.origin_of(M.options.server)
end

return M
