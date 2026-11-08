-- The public API (`/api/v1`, docs/public-api.md) with an OAuth bearer token. A 401 refreshes
-- the token once and repeats the request with the same Idempotency-Key, so a submission is
-- never made twice. Refusals are RFC 9457 problem details with a stable `code`.

local config = require("programavimas.config")
local http = require("programavimas.http")
local oauth = require("programavimas.oauth")
local session = require("programavimas.session")

local M = {}

local PREFIX = "/api/v1"

---@class programavimas.ApiError
---@field kind "signed_out"|"expired"|"scope"|"network"|"refused"|"invalid"
---@field status integer?
---@field problem table?  The problem details (`code`, `detail`, `resetsAt`, …)
---@field retry_after string?

local meta_cache = {}

--- The server's OAuth metadata, discovered once per origin.
---@param origin string
---@return table? meta, table? err
function M.metadata(origin)
  if meta_cache[origin] then return meta_cache[origin], nil end
  local meta, err = oauth.discover(origin)
  if meta then meta_cache[origin] = meta end
  return meta, err
end

--- A version 4 UUID for Idempotency-Key.
function M.uuid()
  local bytes = { assert(vim.uv.random(16)):byte(1, 16) }
  bytes[7] = bit.bor(bit.band(bytes[7], 0x0f), 0x40)
  bytes[9] = bit.bor(bit.band(bytes[9], 0x3f), 0x80)
  local hex = {}
  for _, byte in ipairs(bytes) do table.insert(hex, ("%02x"):format(byte)) end
  local s = table.concat(hex)
  return ("%s-%s-%s-%s-%s"):format(s:sub(1, 8), s:sub(9, 12), s:sub(13, 16), s:sub(17, 20), s:sub(21))
end

--- The `error` of a `WWW-Authenticate: Bearer …` challenge (RFC 6750 §3).
---@param header string?
function M.bearer_error(header)
  if not header or not header:lower():match("^%s*bearer") then return nil end
  return header:match('error="([^"]*)"')
end

--- Calls the API inside a task. Returns the decoded body, or nil and the error.
---@param method "GET"|"POST"|"DELETE"
---@param path string  Below /api/v1, with its query
---@param body table?  Sent as JSON
---@return any data, programavimas.ApiError? err
function M.call(method, path, body)
  local origin = config.origin()
  if not origin then return nil, { kind = "signed_out" } end
  local meta_of = function() return M.metadata(origin) end
  local idempotency = method == "POST" and M.uuid() or nil
  local stale
  for attempt = 1, 2 do
    local token, reason = session.access_token(origin, meta_of, stale)
    if not token then return nil, { kind = reason or "signed_out" } end
    local headers = { Authorization = "Bearer " .. token, Accept = "application/json" }
    if body then headers["Content-Type"] = "application/json" end
    if idempotency then headers["Idempotency-Key"] = idempotency end
    local response = http.request({
      method = method,
      url = origin .. PREFIX .. path,
      headers = headers,
      body = body and vim.json.encode(body) or nil,
    })
    if not response then return nil, { kind = "network" } end
    if response.status == 401 then
      local challenge = M.bearer_error(response.headers["www-authenticate"])
      if challenge == "insufficient_scope" then return nil, { kind = "scope", status = 401 } end
      if attempt == 2 then
        session.set(origin, nil)
        return nil, { kind = "expired", status = 401 }
      end
      stale = token
    elseif response.status == 403 and M.bearer_error(response.headers["www-authenticate"]) == "insufficient_scope" then
      return nil, { kind = "scope", status = 403 }
    elseif response.status >= 200 and response.status < 300 then
      if response.status == 204 then return {}, nil end
      local data = http.json(response.body)
      if data == nil then return nil, { kind = "invalid", status = response.status } end
      return data, nil
    else
      local problem = http.json(response.body)
      return nil, {
        kind = type(problem) == "table" and problem.code and "refused" or "invalid",
        status = response.status,
        problem = type(problem) == "table" and problem or nil,
        retry_after = response.headers["retry-after"],
      }
    end
  end
  return nil, { kind = "expired" }
end

-- ------------------------------------------------------------------ resources

---@param value string
local function seg(value) return http.encode(value) end

function M.me() return M.call("GET", "/me") end

--- Every course of the caller with its topics and problems (`GET /courses`, then each
--- course's problems at once).
---@return table[]? courses, programavimas.ApiError? err
function M.courses()
  local async = require("programavimas.async")
  local summaries, cursor = {}, nil
  repeat
    local page, err = M.call("GET", "/courses?limit=100" .. (cursor and "&cursor=" .. http.encode(cursor) or ""))
    if not page then return nil, err end
    vim.list_extend(summaries, page.items or {})
    cursor = page.nextCursor
  until not cursor
  local loaded = async.all(vim.tbl_map(function(summary)
    return function()
      local problems, err = M.call("GET", "/courses/" .. seg(summary.id) .. "/problems")
      return { summary = summary, problems = problems, err = err }
    end
  end, summaries))
  local courses = {}
  for _, entry in ipairs(loaded) do
    if not entry.problems then return nil, entry.err end
    table.insert(courses, {
      id = entry.summary.id,
      title = entry.summary.title,
      mark = entry.summary.mark,
      topics = entry.problems.topics or {},
    })
  end
  return courses, nil
end

local function problem_path(course_id, problem_id)
  return "/courses/" .. seg(course_id) .. "/problems/" .. seg(problem_id)
end

function M.problem(course_id, problem_id) return M.call("GET", problem_path(course_id, problem_id)) end

function M.drafts(course_id, problem_id)
  return M.call("GET", problem_path(course_id, problem_id) .. "/drafts")
end

--- Saves the caller's draft of a language (`{ language, code, savedAt }`); answers `{ serverAt }`.
---@param course_id string
---@param problem_id string
---@param body { language: string, code: string, savedAt: string }
function M.save_draft(course_id, problem_id, body)
  return M.call("POST", problem_path(course_id, problem_id) .. "/drafts", body)
end

---@param request { language: string, source: string, input: table }
function M.run(course_id, problem_id, request)
  return M.call("POST", problem_path(course_id, problem_id) .. "/runs", request)
end

---@param request { language: string, source: string }
function M.submit(course_id, problem_id, request)
  return M.call("POST", problem_path(course_id, problem_id) .. "/submissions", request)
end

function M.get_run(id) return M.call("GET", "/runs/" .. seg(id)) end

function M.get_submission(id) return M.call("GET", "/submissions/" .. seg(id)) end

---@param query { limit: integer?, courseId: string?, problemId: string? }?
function M.submissions(query)
  query = query or {}
  local parts = { "limit=" .. tostring(query.limit or 20) }
  for _, key in ipairs({ "courseId", "problemId" }) do
    if query[key] then table.insert(parts, key .. "=" .. http.encode(query[key])) end
  end
  return M.call("GET", "/submissions?" .. table.concat(parts, "&"))
end

--- The caller's newest submission of a problem with its code, or nil.
function M.latest_submission(course_id, problem_id)
  local page, err = M.submissions({ limit = 1, courseId = course_id, problemId = problem_id })
  if not page then return nil, err end
  local latest = (page.items or {})[1]
  if not latest then return nil, nil end
  return M.get_submission(latest.id)
end

--- A course problem's page in the web app (Excel tasks have no detail in the API).
function M.problem_page(course_id, problem_id)
  return (config.origin() or "") .. "/courses/" .. seg(course_id) .. "/problems/" .. seg(problem_id)
end

return M
