-- Signing in and out, and who is signed in. Signing in opens the consent page in the browser
-- and receives the code on a loopback port; on a machine without a browser (over SSH), or with
-- `:Programavimas login device`, a code is typed on another device instead. Signing out
-- revokes the grant on the server; the solution files stay.

local api = require("programavimas.api")
local async = require("programavimas.async")
local config = require("programavimas.config")
local http = require("programavimas.http")
local i18n = require("programavimas.i18n")
local oauth = require("programavimas.oauth")
local session = require("programavimas.session")
local ui = require("programavimas.ui")
local t = i18n.t

local M = {}

---@type table?  `/me` of the signed-in account, once loaded
M.me = nil

local function remote()
  return (vim.env.SSH_CONNECTION or vim.env.SSH_TTY or "") ~= ""
end

--- The account (`/me`), loaded once per session; sets the strings' language. Inside a task.
---@return table? me, programavimas.ApiError? err
function M.load()
  if M.me then return M.me, nil end
  local me, err = api.me()
  if me then
    M.me = me
    i18n.account = me.language == "en" and "en" or "lt"
  end
  return me, err
end

function M.signed_in()
  local origin = config.origin()
  return origin ~= nil and session.get(origin) ~= nil
end

--- The code and the address to type it at, in a small window; returns its closer.
---@param start programavimas.DeviceStart
local function show_device_code(start)
  local lines = {
    "",
    "  " .. t("auth.deviceSteps", { url = start.verification_uri }),
    "",
    "      " .. start.user_code,
    "",
    "  " .. t("auth.deviceWaiting"),
    "",
  }
  local width = 0
  for _, line in ipairs(lines) do width = math.max(width, vim.fn.strdisplaywidth(line) + 2) end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_extmark(buf, ui.ns, 3, 0, { end_col = #lines[4], hl_group = "ProgramavimasTitle" })
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = #lines,
    row = math.floor((vim.o.lines - #lines) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. t("auth.deviceTitle") .. " ",
    title_pos = "center",
  })
  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      close()
      oauth.cancel()
    end, { buffer = buf, nowait = true })
  end
  if not remote() and start.verification_uri_complete then
    pcall(vim.ui.open, start.verification_uri_complete)
  end
  return close
end

local FAILURES = {
  network = "error.network",
  metadata = "auth.badMetadata",
  denied = "auth.denied",
  timeout = "auth.timedOut",
  cancelled = "auth.cancelled",
}

--- Signs in: `method` "browser" or "device"; nil chooses by whether this is a remote session.
---@param method? "browser"|"device"
function M.login(method)
  async.run(function()
    local origin = config.origin()
    if not origin then
      return ui.error(t("auth.badServer", { server = tostring(config.options.server) }))
    end
    if vim.fn.executable("curl") == 0 then return ui.error(t("error.curl")) end
    local meta, discover_err = api.metadata(origin)
    if not meta then
      return ui.error(t(FAILURES[discover_err and discover_err.kind or "network"] or "auth.failed", { server = origin }))
    end
    local tokens, err
    if method == "device" or (method == nil and remote()) then
      tokens, err = oauth.login_device(meta, show_device_code)
    else
      tokens, err = oauth.login_browser(meta, function(url)
        -- `vim.ui.open` answers nil and a reason when nothing can open a browser here.
        local ok, opener = pcall(vim.ui.open, url)
        local opened = ok and opener ~= nil
        ui.notify(t("auth.waiting") .. (opened and "" or "\n" .. t("auth.openUrl", { url = url })))
      end)
    end
    if not tokens then
      local kind = err and err.kind or "failed"
      if kind == "cancelled" then return ui.notify(t("auth.cancelled")) end
      return ui.error(t(FAILURES[kind] or "auth.failed", { server = origin }))
    end
    -- Whose tokens these are: `/me` with the new token, before anything is stored.
    local response = http.request({
      url = origin .. "/api/v1/me",
      headers = { Authorization = "Bearer " .. tokens.access_token, Accept = "application/json" },
    })
    local me = response and response.status == 200 and http.json(response.body) or nil
    if type(me) ~= "table" or type(me.id) ~= "string" then return ui.error(t("auth.failed")) end
    local previous = session.get(origin)
    if previous and previous.accountId ~= me.id then
      -- Someone else: nothing of the previous account stays on screen.
      require("programavimas.statement").forget()
      require("programavimas.judge").forget()
    end
    session.set(origin, session.from_tokens(tokens, { id = me.id, name = me.name or me.username or "" }))
    M.me = me
    i18n.account = me.language == "en" and "en" or "lt"
    ui.notify(t("auth.signedIn", { name = me.name or me.username }))
    require("programavimas.courses").refresh()
  end)
end

--- Signs out: revokes the grant on the server, forgets the tokens; the files stay.
function M.logout()
  async.run(function()
    local origin = config.origin()
    local current = origin and session.get(origin)
    if not origin or not current then return ui.notify(t("auth.notSignedIn")) end
    local meta = api.metadata(origin)
    if meta and current.refreshToken then oauth.revoke(meta, current.refreshToken) end
    session.set(origin, nil)
    M.me = nil
    i18n.account = nil
    require("programavimas.courses").forget()
    require("programavimas.judge").forget()
    require("programavimas.statement").forget()
    ui.notify(t("auth.signedOutFiles"))
  end)
end

--- A short menu: who is signed in, the website, the solutions folder, sign out.
function M.menu()
  async.run(function()
    if not M.signed_in() then return ui.notify(t("auth.notSignedIn")) end
    local me, err = M.load()
    if not me then return ui.error(ui.api_message(err)) end
    local solutions = require("programavimas.solutions")
    local root = solutions.root()
    local items = {
      { label = t("account.openInBrowser"), run = function() vim.ui.open(config.origin()) end },
      { label = t("account.changeFolder"), run = function() async.run(function()
        local path = solutions.choose_root()
        if path then ui.notify(t("folder.changed", { path = vim.fn.fnamemodify(path, ":~") })) end
      end) end },
      { label = t("account.signOut"), run = M.logout },
    }
    local prompt = table.concat({
      t("account.signedInAs", { name = me.name }),
      t("account.server", { server = config.origin() }),
      root and t("account.folder", { folder = vim.fn.fnamemodify(root, ":~") }) or t("account.noFolder"),
    }, " · ")
    vim.ui.select(items, { prompt = prompt, format_item = function(item) return item.label end }, function(item)
      if item then item.run() end
    end)
  end)
end

return M
