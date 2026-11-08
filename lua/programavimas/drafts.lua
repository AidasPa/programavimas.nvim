-- Draft sync: each language's main file follows the student's draft on the server, the copy
-- the web editor saves as they type, so work moves between the browser, VS Code and Neovim.
-- The rule is the web editor's (`apps/web/src/features/code-workspace/server-drafts.ts`) and
-- the VS Code extension's, adapted to files:
--
-- * Saving a main file sends it to the server: one request per file at a time, the newest
--   content only, a moment after the save so a burst of saves is one request.
-- * Opening a main file, entering its buffer or coming back to Neovim (at most every 15 s per
--   file) compares the file with the server's copy. A sync record per file, the server copy
--   (`serverAt`) the file last matched and the file's hash then, says which side changed:
--   only the file → send it; only the server's copy → take it (one undoable change, saved);
--   both → ask (use the saved draft, keep this file, compare).
-- * A blank file, or one still holding the starter code, takes the server's copy at once.
-- * Unsaved changes in the buffer are never replaced without asking.
--
-- Records live in state.json per server, account, course, problem and language, not in the
-- `.programavimas` marker, which each client rewrites with only the fields it knows.

local api = require("programavimas.api")
local async = require("programavimas.async")
local config = require("programavimas.config")
local i18n = require("programavimas.i18n")
local paths = require("programavimas.paths")
local session = require("programavimas.session")
local solutions = require("programavimas.solutions")
local time = require("programavimas.time")
local ui = require("programavimas.ui")
local t = i18n.t

local M = {}

M.CHECK_EVERY_S = 15
M.SAVE_DELAY_MS = 1000
--- The API's limit on a draft (`draftSaveRequestSchema`).
M.MAX_CODE = 200000

---@class programavimas.DraftRecord
---@field serverAt string  The server copy the file last matched
---@field sha256 string    The file's hash then

---@class programavimas.ServerDraft
---@field language string
---@field code string
---@field savedAt string  When the author's editor saved it
---@field serverAt string The server's time of this copy, which identifies it

---@alias programavimas.DraftAction "none"|"record"|"push"|"take"|"ask"

--- What to do with a main file and the server's copy of its language. Pure.
---@param input { text: string, record: programavimas.DraftRecord?, draft: programavimas.ServerDraft?, pristine: boolean, modified: boolean }
---   `text`: the file as saved; `pristine`: blank or still the starter code; `modified`: the
---   buffer has unsaved changes
---@return programavimas.DraftAction
function M.decide(input)
  local text, record, draft = input.text, input.record, input.draft
  local unchanged = record ~= nil and record.sha256 == vim.fn.sha256(text)
  if not draft then
    -- Nothing on the server (or removed there): send work it has not seen.
    if input.pristine or unchanged then return "none" end
    return "push"
  end
  if draft.code == text then return "record" end
  -- The server still holds the copy the file last matched: only the file changed.
  if record ~= nil and record.serverAt == draft.serverAt then return "push" end
  -- Only the server's copy changed (or the file holds nothing of the student's).
  if (unchanged or input.pristine) and not input.modified then return "take" end
  return "ask"
end

-- ------------------------------------------------------------------ records

---@return table<string, programavimas.DraftRecord>
local function records()
  local value = solutions.state().drafts
  return type(value) == "table" and value or {}
end

---@param key string
---@return programavimas.DraftRecord?
local function record_of(key)
  local value = records()[key]
  if type(value) == "table" and type(value.serverAt) == "string" and type(value.sha256) == "string" then
    return value
  end
  return nil
end

---@param key string
---@param value programavimas.DraftRecord?
local function set_record(key, value)
  local all = records()
  all[key] = value
  solutions.remember("drafts", all)
end

-- ------------------------------------------------------------------ which files sync

---@class programavimas.DraftTarget
---@field key string
---@field solution programavimas.Solution
---@field file string  The main file's name

--- The buffer's main file and its record key, or nil (not a main file, signed out).
---@param buf integer
---@return programavimas.DraftTarget?
--- The record key of a solution's main file for the signed-in account (as VS Code keys it).
---@param solution programavimas.Solution
---@return string?
local function key_of(solution)
  local origin = config.origin()
  local current = origin and session.get(origin)
  if not current or type(current.accountId) ~= "string" then return nil end
  return table.concat({ origin, current.accountId, solution.marker.courseId, solution.marker.problemId, solution.language }, "|")
end

local function target_of(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return nil end
  local name = vim.api.nvim_buf_get_name(buf)
  local solution = solutions.solution_for(name)
  if not solution or not paths.is_editor_language(solution.language) then return nil end
  local file = paths.solution_file(solution.language)
  if vim.fs.basename(name) ~= file then return nil end
  local key = key_of(solution)
  if not key then return nil end
  return { key = key, solution = solution, file = file }
end

---@param epoch number
local function iso(epoch) return os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(epoch)) end

--- "09:40" today, else the date too (Lithuanian time).
---@param value string
local function when(value)
  local epoch = time.parse(value)
  if not epoch then return value end
  return (os.time() - epoch < 18 * 3600) and time.clock(epoch) or time.date_time(epoch)
end

---@param target programavimas.DraftTarget
--- The main file as saved, with Windows line ends as `\n`: the web editor's and VS Code's
--- copies use `\n`, so a CRLF file compares equal to the same code.
---@param target programavimas.DraftTarget
local function saved_text(target)
  local text = (solutions.read(target.solution.main) or ""):gsub("\r\n", "\n")
  return text
end

-- ------------------------------------------------------------------ sending

---@class programavimas.DraftQueue
---@field pending { code: string, savedAt: string }?
---@field busy boolean
---@field timer uv.uv_timer_t?

---@type table<string, programavimas.DraftQueue>
local queues = {}
---@type table<string, "synced"|"pending">
M.status = {}
---@type table<string, true>  Files the server refused (no longer in the course): not synced
local stopped = {}
---@type table<string, true>
local warned = {}
---@type table<string, integer>
local checked = {}
---@type table<string, true>
local checking = {}
---@type table<string, true>  A file being replaced with the server's copy: its save is not sent
local applying = {}
---@type table<string, true>  A question is open for the file
local asking = {}
---@type table<string, integer>  Counts saves per file, so a check that crossed one is dropped
local saves = {}
local generation = 0

---@param target programavimas.DraftTarget
local function send(target)
  local queue = queues[target.key]
  if not queue or queue.busy or not queue.pending then return end
  local next = queue.pending
  queue.pending = nil
  queue.busy = true
  local started = generation
  local marker = target.solution.marker
  async.run(function()
    local saved, err = api.save_draft(marker.courseId, marker.problemId, {
      language = target.solution.language,
      code = next.code,
      savedAt = next.savedAt,
    })
    queue.busy = false
    if started ~= generation then return end
    if saved then
      set_record(target.key, saved.serverAt and { serverAt = saved.serverAt, sha256 = vim.fn.sha256(next.code) } or nil)
      M.status[target.key] = queue.pending and "pending" or "synced"
    elseif err and (err.status == 403 or err.status == 404) then
      -- No longer in the course, or the problem left it: this file stops syncing.
      stopped[target.key] = true
      M.status[target.key] = nil
    elseif err and err.status and err.status >= 400 and err.status < 500 and err.status ~= 408 and err.status ~= 429 then
      -- Refused as it is: the next save sends again.
      M.status[target.key] = "pending"
    else
      -- Offline, signed out or the server is busy: goes with the next save or check.
      queue.pending = queue.pending or next
      M.status[target.key] = "pending"
      vim.cmd.redrawstatus()
      return
    end
    -- A newer save came in meanwhile.
    if queue.pending then send(target) end
    vim.cmd.redrawstatus()
  end, function()
    queue.busy = false
  end)
end

--- Sends a file's content after `delay_ms`, replacing anything not sent yet.
---@param target programavimas.DraftTarget
---@param code string
---@param saved_at string
---@param delay_ms integer
local function schedule(target, code, saved_at, delay_ms)
  if stopped[target.key] then return end
  if #code > M.MAX_CODE then
    if not warned[target.key] then
      warned[target.key] = true
      ui.warn(t("drafts.tooLarge", { file = target.file }))
    end
    return
  end
  local queue = queues[target.key] or { busy = false }
  queues[target.key] = queue
  saves[target.key] = (saves[target.key] or 0) + 1
  queue.pending = { code = code, savedAt = saved_at }
  M.status[target.key] = "pending"
  if queue.timer then queue.timer:stop() else queue.timer = vim.uv.new_timer() end
  queue.timer:start(delay_ms, 0, vim.schedule_wrap(function() send(target) end))
end

--- A new or blank main file was just filled from the server: from its draft (they match), or
--- from the latest submission because that is newer than the draft (the file supersedes it,
--- so the first check sends it instead of asking).
---@param solution programavimas.Solution
---@param draft programavimas.ServerDraft?  The server's draft of the file's language
---@param code string  What the file was filled with
function M.started(solution, draft, code)
  local key = draft and key_of(solution)
  if not key then return end
  set_record(key, { serverAt = draft.serverAt, sha256 = vim.fn.sha256((code:gsub("\r\n", "\n"))) })
end

--- After a solution buffer was written: its main file goes to the server.
---@param buf integer
function M.saved(buf)
  local target = target_of(buf)
  if not target or applying[target.key] or stopped[target.key] then return end
  local code = saved_text(target)
  local record = record_of(target.key)
  if record and record.sha256 == vim.fn.sha256(code) and not (queues[target.key] or {}).pending then
    M.status[target.key] = "synced"
    return
  end
  schedule(target, code, iso(os.time()), M.SAVE_DELAY_MS)
end

-- ------------------------------------------------------------------ comparing

--- Replaces the buffer with the server's copy (one undoable change) and saves it.
---@param target programavimas.DraftTarget
---@param buf integer
---@param draft programavimas.ServerDraft
local function take(target, buf, draft)
  local lines = vim.split(draft.code, "\n", { plain = true })
  if #lines > 1 and lines[#lines] == "" then table.remove(lines) end
  applying[target.key] = true
  local ok, err = pcall(function()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_call(buf, function() vim.cmd("silent write!") end)
  end)
  applying[target.key] = nil
  if not ok then return ui.error(tostring(err)) end
  -- Recorded as saved, final newline included; a difference from the server's copy goes
  -- back with the next check.
  set_record(target.key, { serverAt = draft.serverAt, sha256 = vim.fn.sha256(saved_text(target)) })
  M.status[target.key] = "synced"
  ui.notify(t("drafts.updated", { file = target.file, time = when(draft.savedAt) }))
end

--- The server's copy beside the file in a diff tab; returns its closer.
---@param target programavimas.DraftTarget
---@param buf integer
---@param draft programavimas.ServerDraft
local function compare(target, buf, draft)
  vim.cmd("tab sbuffer " .. buf)
  local tab = vim.api.nvim_get_current_tabpage()
  vim.cmd.diffthis()
  local name = ("programavimas://draft/%s/%s/%s"):format(target.solution.marker.courseId, target.solution.marker.problemId, target.file)
  local existing = vim.fn.bufnr(name)
  if existing ~= -1 then vim.api.nvim_buf_delete(existing, { force = true }) end
  vim.cmd("leftabove vnew")
  local scratch = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_name(scratch, name)
  local lines = vim.split(draft.code, "\n", { plain = true })
  if #lines > 1 and lines[#lines] == "" then table.remove(lines) end
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, lines)
  vim.bo[scratch].buftype = "nofile"
  vim.bo[scratch].bufhidden = "wipe"
  vim.bo[scratch].swapfile = false
  vim.bo[scratch].modifiable = false
  vim.bo[scratch].filetype = vim.bo[buf].filetype
  vim.wo.winbar = t("drafts.compareSaved", { time = when(draft.savedAt) })
  vim.cmd.diffthis()
  vim.cmd.wincmd("p")
  vim.wo.winbar = t("drafts.compareFile", { file = target.file })
  return function()
    if vim.api.nvim_tabpage_is_valid(tab) and #vim.api.nvim_list_tabpages() > 1 then
      vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(tab))
    end
  end
end

---@param target programavimas.DraftTarget
---@param buf integer
---@param draft programavimas.ServerDraft
local function ask(target, buf, draft)
  local saved_at = when(draft.savedAt)
  local function choose(options)
    return async.await(function(done)
      vim.ui.select(options, {
        prompt = t("drafts.differs", { file = target.file, time = saved_at }),
        format_item = function(option) return option.label end,
      }, done)
    end)
  end
  local take_option = { id = "take", label = t("drafts.useSaved", { time = saved_at }) }
  local keep_option = { id = "keep", label = t("drafts.keep") }
  asking[target.key] = true
  local choice = choose({ take_option, keep_option, { id = "compare", label = t("drafts.compare") } })
  if choice and choice.id == "compare" then
    local close = compare(target, buf, draft)
    choice = choose({ take_option, keep_option })
    if choice then close() end
  end
  asking[target.key] = nil
  if not choice then return ui.notify(t("drafts.decideLater")) end
  if not vim.api.nvim_buf_is_valid(buf) then return end
  if choice.id == "take" then
    take(target, buf, draft)
  else
    schedule(target, saved_text(target), iso(os.time()), 0)
  end
end

--- Compares a main file with the server's copy and acts on it (see the top). `force` skips
--- the 15-second spacing.
---@param buf integer
---@param force? boolean
function M.check(buf, force)
  local target = target_of(buf)
  if not target or stopped[target.key] or checking[target.key] or asking[target.key] then return end
  local queue = queues[target.key]
  if queue and queue.busy then return end
  -- A save that could not be sent goes first; the check comes after it.
  if queue and queue.pending then return send(target) end
  local now = os.time()
  if not force and checked[target.key] and now - checked[target.key] < M.CHECK_EVERY_S then return end
  checked[target.key] = now
  checking[target.key] = true
  local started, saved_before = generation, saves[target.key]
  local marker = target.solution.marker
  async.run(function()
    local list, err = api.drafts(marker.courseId, marker.problemId)
    checking[target.key] = nil
    if started ~= generation or not vim.api.nvim_buf_is_valid(buf) then return end
    -- Saved meanwhile: the server's answer may predate that save, and the save settles it.
    if saves[target.key] ~= saved_before then return end
    if not list then
      if err and (err.status == 403 or err.status == 404) then stopped[target.key] = true end
      return
    end
    local draft
    for _, item in ipairs(list.items or {}) do
      if item.language == target.solution.language then draft = item end
    end
    local text = saved_text(target)
    local detail = require("programavimas.problems").details[marker.courseId .. "|" .. marker.problemId]
    local starter = detail and type(detail.starterCode) == "table" and detail.starterCode[target.solution.language] or nil
    local action = M.decide({
      text = text,
      record = record_of(target.key),
      draft = draft,
      pristine = vim.trim(text) == "" or (type(starter) == "string" and text == starter),
      modified = vim.bo[buf].modified,
    })
    if action == "record" then
      set_record(target.key, { serverAt = draft.serverAt, sha256 = vim.fn.sha256(text) })
      M.status[target.key] = "synced"
    elseif action == "push" then
      local stat = vim.uv.fs_stat(target.solution.main)
      schedule(target, text, iso(stat and stat.mtime.sec or now), 0)
    elseif action == "take" then
      take(target, buf, draft)
    elseif action == "ask" then
      ask(target, buf, draft)
    elseif record_of(target.key) then
      M.status[target.key] = "synced"
    end
    vim.cmd.redrawstatus()
  end, function()
    checking[target.key] = nil
  end)
end

-- ------------------------------------------------------------------ wiring

local group

--- Starts syncing a solution buffer (called when it is attached).
---@param buf integer
function M.attach(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local solution = solutions.solution_for(name)
  if not solution or vim.fs.basename(name) ~= paths.solution_file(solution.language) then return end
  group = group or vim.api.nvim_create_augroup("programavimas_drafts", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", { group = group, buffer = buf, callback = function() M.saved(buf) end })
  vim.api.nvim_create_autocmd("BufEnter", { group = group, buffer = buf, callback = function() M.check(buf) end })
  if not M.focus then
    M.focus = vim.api.nvim_create_autocmd("FocusGained", {
      group = group,
      callback = function() M.check(vim.api.nvim_get_current_buf()) end,
    })
  end
  M.check(buf, true)
end

--- `:Programavimas sync`: compare the current main file now.
function M.sync_now()
  local buf = vim.api.nvim_get_current_buf()
  if not target_of(buf) then return ui.notify(t("drafts.notMain"), vim.log.levels.WARN) end
  M.check(buf, true)
end

--- For the status line: "☁" once the server holds the file as saved, "↑" while sending.
---@param buf integer
---@return string?
function M.statusline(buf)
  local target = target_of(buf)
  local status = target and M.status[target.key]
  if not status then return nil end
  return status == "synced" and config.options.icons.synced or config.options.icons.syncing
end

--- On signing out or in as someone else: nothing waiting is sent for the previous account.
function M.forget()
  generation = generation + 1
  for _, queue in pairs(queues) do
    if queue.timer then
      queue.timer:stop()
      queue.timer:close()
    end
  end
  queues, checked, checking, stopped, warned, applying, asking, saves = {}, {}, {}, {}, {}, {}, {}, {}
  M.status = {}
end

return M
