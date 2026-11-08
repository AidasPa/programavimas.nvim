-- Neovim as an OAuth 2.0 public client of the web app (docs/public-api.md §3): metadata
-- discovery (RFC 8414) checked against the configured server, the authorization code grant
-- with PKCE (S256), `state` and `iss` (RFC 9207) through a one-shot loopback listener
-- (RFC 8252 §7.3), the device authorization grant (RFC 8628) for a Neovim without a browser,
-- refresh-token rotation and revocation (RFC 7009). Codes, verifiers and tokens are never
-- shown or logged.

local async = require("programavimas.async")
local http = require("programavimas.http")

local M = {}

M.CLIENT_ID = "programavimas-nvim"
M.SCOPES = { "profile:read", "courses:read", "runs:write", "submissions:read", "submissions:write" }
local DEVICE_GRANT = "urn:ietf:params:oauth:grant-type:device_code"
local LOGIN_TIMEOUT_MS = 5 * 60 * 1000

---@class programavimas.OAuthError
---@field kind "network"|"metadata"|"denied"|"timeout"|"cancelled"|"failed"|"invalid_grant"

---@param kind string
local function failure(kind) return { kind = kind } end

---@param bytes string
local function base64url(bytes)
  return (vim.base64.encode(bytes):gsub("%+", "-"):gsub("/", "_"):gsub("=+$", ""))
end

---@param hex string
local function from_hex(hex)
  return (hex:gsub("%x%x", function(pair) return string.char(tonumber(pair, 16)) end))
end

--- A random URL-safe string of `bytes` random bytes.
function M.random(bytes)
  return base64url(assert(vim.uv.random(bytes)))
end

--- The PKCE S256 challenge of a verifier (RFC 7636 §4.2).
function M.challenge(verifier)
  return base64url(from_hex(vim.fn.sha256(verifier)))
end

---@param value string?
---@param origin string
local function on_origin(value, origin)
  return type(value) == "string" and (value == origin or vim.startswith(value, origin .. "/"))
end

--- The rules the metadata must meet before anyone is sent to it: the issuer is exactly the
--- configured server, every endpoint is on that origin, and PKCE uses S256. Nil when fine.
---@param meta table
---@param origin string
---@return string?
function M.metadata_problem(meta, origin)
  if meta.issuer ~= origin then return "issuer" end
  for _, name in ipairs({ "authorization_endpoint", "token_endpoint" }) do
    if not on_origin(meta[name], origin) then return name end
  end
  for _, name in ipairs({ "revocation_endpoint", "device_authorization_endpoint" }) do
    if meta[name] ~= nil and not on_origin(meta[name], origin) then return name end
  end
  local methods = meta.code_challenge_methods_supported
  if methods ~= nil and not vim.tbl_contains(methods, "S256") then return "pkce" end
  return nil
end

---@param origin string
---@return table? meta, programavimas.OAuthError? err
function M.discover(origin)
  local response = http.request({ url = origin .. "/.well-known/oauth-authorization-server" })
  if not response then return nil, failure("network") end
  local meta = response.status == 200 and http.json(response.body) or nil
  if type(meta) ~= "table" or M.metadata_problem(meta, origin) then return nil, failure("metadata") end
  return meta, nil
end

--- A form POST to an OAuth endpoint; the JSON body (tokens, or `{ error }`) and the status.
---@param url string
---@param fields table<string, string>
---@return table? body, integer? status
local function post_form(url, fields)
  local response = http.request({
    method = "POST",
    url = url,
    headers = { ["Content-Type"] = "application/x-www-form-urlencoded", Accept = "application/json" },
    body = http.form(fields),
  })
  if not response then return nil, nil end
  return http.json(response.body) or {}, response.status
end

---@class programavimas.Tokens
---@field access_token string
---@field expires_in number?
---@field refresh_token string?
---@field scope string?

---@param body table?
---@param status integer?
---@return programavimas.Tokens? tokens, programavimas.OAuthError? err
local function token_result(body, status)
  if not body then return nil, failure("network") end
  if status == 200 and type(body.access_token) == "string" then return body, nil end
  if body.error == "invalid_grant" then return nil, failure("invalid_grant") end
  if body.error == "access_denied" then return nil, failure("denied") end
  return nil, failure("failed")
end

-- ------------------------------------------------------------------ loopback

local function done_page(title)
  return table.concat({
    "<!doctype html><html><meta charset=utf-8><meta name=viewport content='width=device-width'>",
    "<title>", title, "</title><body style='font-family:system-ui,sans-serif;max-width:32rem;",
    "margin:15vh auto;padding:0 1rem'><h1 style='font-size:1.25rem'>", title,
    "</h1><p>You can close this tab and return to Neovim.</p></body></html>",
  })
end

---@param client uv.uv_tcp_t
---@param status string
---@param body string
local function answer(client, status, body)
  client:write(table.concat({
    "HTTP/1.1 ", status, "\r\n",
    "Content-Type: text/html; charset=utf-8\r\n",
    "Cache-Control: no-store\r\n",
    "Connection: close\r\n",
    "Content-Length: ", tostring(#body), "\r\n\r\n", body,
  }), function() client:close() end)
end

--- The pending loopback sign-in, so a second `login` cancels the first.
local pending

function M.cancel()
  if pending then pending("cancelled") end
end

--- Waits for the browser to come back to `http://127.0.0.1:<port>/callback?state=…`.
---@param state string
---@param on_listening fun(redirect_uri: string)
---@return table<string,string>? params, string? err  "timeout"|"cancelled"|"network"
local function await_callback(state, on_listening)
  return async.await(function(done)
    local server = vim.uv.new_tcp()
    local timer = vim.uv.new_timer()
    local finished = false
    local function finish(params, err)
      if finished then return end
      finished = true
      pending = nil
      timer:stop()
      timer:close()
      if not server:is_closing() then server:close() end
      done(params, err)
    end
    pending = function(reason) finish(nil, reason) end
    local ok = server:bind("127.0.0.1", 0)
    if not ok then return finish(nil, "network") end
    server:listen(8, function(listen_err)
      if listen_err then return end
      local client = vim.uv.new_tcp()
      server:accept(client)
      local buffer = ""
      client:read_start(function(read_err, chunk)
        if read_err or not chunk then
          client:close()
          return
        end
        buffer = buffer .. chunk
        if #buffer > 16384 then
          client:read_stop()
          return answer(client, "400 Bad Request", "")
        end
        if not buffer:find("\r\n\r\n", 1, true) then return end
        client:read_stop()
        local target = buffer:match("^GET (%S+) HTTP/1%.[01]\r\n")
        local path, query = (target or ""):match("^([^?]*)%??(.*)$")
        local params = http.parse_query(query or "")
        if path ~= "/callback" or params.state ~= state then
          return answer(client, "404 Not Found", "Not found")
        end
        answer(client, "200 OK", done_page(params.error and "Sign-in was cancelled" or "Signed in"))
        vim.schedule(function() finish(params, nil) end)
      end)
    end)
    timer:start(LOGIN_TIMEOUT_MS, 0, function() vim.schedule(function() finish(nil, "timeout") end) end)
    local port = server:getsockname().port
    vim.schedule(function() on_listening(("http://127.0.0.1:%d/callback"):format(port)) end)
  end)
end

--- Signs in through the browser: PKCE, `state`, a loopback redirect on a free port.
---@param meta table
---@param on_url fun(url: string)  Called with the authorization URL (opened in the browser)
---@return programavimas.Tokens? tokens, programavimas.OAuthError? err
function M.login_browser(meta, on_url)
  M.cancel()
  local verifier = M.random(32)
  local state = M.random(16)
  local redirect_uri
  local params, err = await_callback(state, function(uri)
    redirect_uri = uri
    on_url(meta.authorization_endpoint .. "?" .. http.form({
      response_type = "code",
      client_id = M.CLIENT_ID,
      redirect_uri = uri,
      scope = table.concat(M.SCOPES, " "),
      state = state,
      code_challenge = M.challenge(verifier),
      code_challenge_method = "S256",
    }))
  end)
  if not params then return nil, failure(err or "failed") end
  if params.error then return nil, failure(params.error == "access_denied" and "denied" or "failed") end
  -- RFC 9207: the response names its issuer, so a code from another server is never used.
  if meta.authorization_response_iss_parameter_supported and params.iss ~= meta.issuer then
    return nil, failure("failed")
  end
  if not params.code then return nil, failure("failed") end
  return token_result(post_form(meta.token_endpoint, {
    grant_type = "authorization_code",
    code = params.code,
    redirect_uri = redirect_uri,
    client_id = M.CLIENT_ID,
    code_verifier = verifier,
  }))
end

-- ------------------------------------------------------------------ device

---@class programavimas.DeviceStart
---@field user_code string
---@field verification_uri string
---@field verification_uri_complete string?

--- Signs in with a code typed on another device (RFC 8628): `on_code` shows it, then the token
--- endpoint is polled at the server's interval until the person allows or refuses.
---@param meta table
---@param on_code fun(start: programavimas.DeviceStart): fun()  Returns a closer for the prompt
---@return programavimas.Tokens? tokens, programavimas.OAuthError? err
function M.login_device(meta, on_code)
  M.cancel()
  if not meta.device_authorization_endpoint then return nil, failure("failed") end
  local start, status = post_form(meta.device_authorization_endpoint, {
    client_id = M.CLIENT_ID,
    scope = table.concat(M.SCOPES, " "),
  })
  if not start then return nil, failure("network") end
  if status ~= 200 or type(start.device_code) ~= "string" or type(start.user_code) ~= "string" then
    return nil, failure("failed")
  end
  local cancelled = false
  pending = function() cancelled = true end
  local close = on_code(start)
  local interval = math.max(1, tonumber(start.interval) or 5)
  local deadline = vim.uv.now() + (tonumber(start.expires_in) or 600) * 1000
  local result, err
  while true do
    async.sleep(interval * 1000)
    if cancelled then
      err = failure("cancelled")
      break
    end
    if vim.uv.now() > deadline then
      err = failure("timeout")
      break
    end
    local body, code = post_form(meta.token_endpoint, {
      grant_type = DEVICE_GRANT,
      device_code = start.device_code,
      client_id = M.CLIENT_ID,
    })
    if body and code == 200 and type(body.access_token) == "string" then
      result = body
      break
    end
    local error_code = body and body.error
    if error_code == "slow_down" then
      interval = interval + 5
    elseif error_code == "access_denied" then
      err = failure("denied")
      break
    elseif error_code == "expired_token" then
      err = failure("timeout")
      break
    elseif error_code ~= "authorization_pending" and body then
      err = failure("failed")
      break
    end
  end
  pending = nil
  close()
  return result, err
end

-- ------------------------------------------------------------------ refresh and revoke

---@param meta table
---@param refresh_token string
---@return programavimas.Tokens? tokens, programavimas.OAuthError? err
function M.refresh(meta, refresh_token)
  return token_result(post_form(meta.token_endpoint, {
    grant_type = "refresh_token",
    refresh_token = refresh_token,
    client_id = M.CLIENT_ID,
  }))
end

--- Ends the grant on the server (a refresh token ends its whole grant). Failures are ignored:
--- the local session is removed either way.
---@param meta table
---@param token string
function M.revoke(meta, token)
  if not meta.revocation_endpoint then return end
  post_form(meta.revocation_endpoint, {
    token = token,
    token_type_hint = "refresh_token",
    client_id = M.CLIENT_ID,
  })
end

return M
