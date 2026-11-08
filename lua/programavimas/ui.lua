-- What every view shares: highlight groups (linked to standard groups, so any colour scheme
-- applies and can override them), the web's state glyphs as plain characters, notifications,
-- and the messages for refusals (the same reasons and words as the web workspace).

local config = require("programavimas.config")
local i18n = require("programavimas.i18n")
local t = i18n.t

local M = {}

M.ns = vim.api.nvim_create_namespace("programavimas")

local LINKS = {
  ProgramavimasSuccess = "DiagnosticOk",
  ProgramavimasDanger = "DiagnosticError",
  ProgramavimasWarning = "DiagnosticWarn",
  ProgramavimasProgress = "DiagnosticInfo",
  ProgramavimasMuted = "Comment",
  ProgramavimasTitle = "Title",
  ProgramavimasHeading = "@markup.heading",
  ProgramavimasAccent = "Special",
  ProgramavimasDiff = "DiffText",
  ProgramavimasFaint = "NonText",
  -- The statement (markdown.lua)
  ProgramavimasStrong = "@markup.strong",
  ProgramavimasEmphasis = "@markup.italic",
  ProgramavimasStrike = "@markup.strikethrough",
  ProgramavimasCode = "@markup.raw",
  ProgramavimasCodeBlock = "CursorLine",
  ProgramavimasMath = "@markup.math",
  ProgramavimasLink = "@markup.link.label",
  ProgramavimasQuote = "@markup.quote",
  ProgramavimasListMarker = "@markup.list",
  ProgramavimasNote = "DiagnosticInfo",
  ProgramavimasHint = "DiagnosticHint",
}

function M.highlights()
  for name, link in pairs(LINKS) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

--- Shape carries the meaning, colour reinforces it; the words always name the state.
---@class programavimas.Glyph
---@field icon string
---@field hl string
---@field label string

---@param status { kind: string, passed?: integer, total?: integer, late?: boolean }
---@return programavimas.Glyph
function M.status_glyph(status)
  local icons = config.options.icons
  if status.kind == "complete" then
    return {
      icon = icons.complete,
      hl = status.late and "ProgramavimasWarning" or "ProgramavimasSuccess",
      label = t(status.late and "status.completeLate" or "status.complete"),
    }
  elseif status.kind == "attempted" then
    return {
      icon = icons.attempted,
      hl = "ProgramavimasProgress",
      label = t("status.attemptedTests", { passed = status.passed, total = status.total }),
    }
  elseif status.kind == "locked" then
    return { icon = icons.locked, hl = "ProgramavimasMuted", label = t("status.locked") }
  end
  return { icon = icons.not_started, hl = "ProgramavimasMuted", label = t("status.not_started") }
end

local VERDICTS = {
  accepted = { "accepted", "ProgramavimasSuccess" },
  wrong_answer = { "failed", "ProgramavimasDanger" },
  presentation_error = { "failed", "ProgramavimasDanger" },
  runtime_error = { "failed", "ProgramavimasDanger" },
  security_violation = { "failed", "ProgramavimasDanger" },
  time_limit_exceeded = { "limit", "ProgramavimasWarning" },
  memory_limit_exceeded = { "limit", "ProgramavimasWarning" },
  idleness_limit_exceeded = { "limit", "ProgramavimasWarning" },
  output_limit_exceeded = { "output", "ProgramavimasWarning" },
  compilation_error = { "compile", "ProgramavimasMuted" },
  checker_error = { "system", "ProgramavimasMuted" },
  system_error = { "system", "ProgramavimasMuted" },
}

---@param verdict string
---@return programavimas.Glyph
function M.verdict_glyph(verdict)
  local look = VERDICTS[verdict] or { "system", "ProgramavimasMuted" }
  return { icon = config.options.icons[look[1]], hl = look[2], label = t("verdict." .. verdict) }
end

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

--- The spinner frame for now: every view that spins shows the same frame.
function M.spinner()
  return SPINNER[math.floor(vim.uv.now() / 100) % #SPINNER + 1]
end

---@param phase string
function M.running(phase)
  return phase == "queued" or phase == "compiling" or phase == "testing"
end

--- A run without a verdict: waiting and running spin; terminal states stay still.
---@param phase string
---@param verdict string?
---@return programavimas.Glyph
function M.run_glyph(phase, verdict)
  if verdict then return M.verdict_glyph(verdict) end
  if M.running(phase) then
    return { icon = M.spinner(), hl = "ProgramavimasProgress", label = t("judging." .. phase) }
  end
  if phase == "cancelled" then return { icon = "⊘", hl = "ProgramavimasMuted", label = t("judging.cancelled") } end
  if phase == "failed" then
    return { icon = config.options.icons.system, hl = "ProgramavimasMuted", label = t("judging.failed") }
  end
  return { icon = config.options.icons.not_started, hl = "ProgramavimasMuted", label = t("judging.finished") }
end

--- The web's difficulty meter: three rising bars, filled by band (0–2 easy, 3–4, 5–10 hard).
---@param difficulty integer?
---@return { text: string, filled: integer }?
function M.difficulty(difficulty)
  if difficulty == nil then return nil end
  local filled = difficulty <= 2 and 1 or difficulty <= 4 and 2 or 3
  return { text = config.options.icons.difficulty, filled = filled }
end

---@param message string
---@param level? integer
function M.notify(message, level)
  vim.notify(message, level or vim.log.levels.INFO, { title = "Programavimas" })
end

---@param message string
function M.error(message) M.notify(message, vim.log.levels.ERROR) end

---@param message string
function M.warn(message) M.notify(message, vim.log.levels.WARN) end

--- The words for an API failure that is not a judge refusal.
---@param err programavimas.ApiError
function M.api_message(err)
  if err.kind == "signed_out" then return t("auth.notSignedIn") end
  if err.kind == "expired" then return t("auth.expired") end
  if err.kind == "scope" then return t("auth.scope") end
  if err.kind == "network" then return t("error.network") end
  if err.kind == "refused" and err.problem and err.problem.code then
    return M.refusal_message(err)
  end
  if err.status == 404 then return t("errors.notFound") end
  return t("error.invalid")
end

local SIMPLE = {
  not_found = "errors.notFound",
  invalid = "errors.invalid",
  failed = "errors.failed",
  language_not_allowed = "errors.language",
  empty_source = "errors.emptySource",
  locked = "errors.locked",
  busy = "errors.busy",
  judging = "errors.judging",
  no_samples = "errors.noSamples",
  custom_during_exam = "errors.customDuringExam",
  version_changed = "errors.versionChanged",
}

---@param seconds string?
local function retry_seconds(seconds)
  if not seconds then return nil end
  return tonumber(vim.trim(seconds))
end

--- Why a run or submission was refused, as the web workspace explains it. An unknown code (a
--- newer server) reads by its HTTP status.
---@param err programavimas.ApiError
function M.refusal_message(err)
  local time = require("programavimas.time")
  local problem = err.problem or {}
  local code = problem.code
  if SIMPLE[code] then return t(SIMPLE[code]) end
  if code == "source_too_large" or code == "input_too_large" then
    local limit = math.floor((tonumber(problem.limitBytes) or (code == "source_too_large" and 262144 or 65536)) / 1024)
    return t(code == "source_too_large" and "errors.sourceTooLarge" or "errors.inputTooLarge", { limit = limit })
  end
  if code == "closed" then
    local at = time.parse(problem.closedAt)
    return at and t("errors.closed", { date = time.date_time(at) }) or t("errors.closedNoDate")
  end
  if code == "no_attempts" then
    local at = time.parse(problem.resetsAt)
    return at and t("errors.noAttempts", { date = time.date_time(at) }) or t("errors.noAttemptsNoDate")
  end
  if code == "rate_limited" then
    local seconds = tonumber(problem.retryAfterSeconds) or retry_seconds(err.retry_after)
    return seconds and t("errors.rateLimited", { seconds = seconds }) or t("errors.rateLimitedNoTime")
  end
  if code == "invalid_token" then return t("auth.expired") end
  if code == "insufficient_scope" then return t("auth.scope") end
  return t(err.status == 404 and "errors.notFound" or "errors.failed")
end

-- ------------------------------------------------------------------ buffers and windows

--- A scratch buffer of ours by name, created once and reused.
---@param name string
---@param filetype string
---@return integer
function M.scratch(name, filetype)
  local existing = vim.fn.bufnr(name)
  if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then return existing end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, name)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = filetype
  return buf
end

--- Replaces a scratch buffer's text and highlights.
---@param buf integer
---@param lines string[]
---@param marks? programavimas.Mark[]
function M.render(buf, lines, marks)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
  vim.api.nvim_buf_clear_namespace(buf, M.ns, 0, -1)
  for _, mark in ipairs(marks or {}) do
    pcall(vim.api.nvim_buf_set_extmark, buf, M.ns, mark.line, mark.col, {
      end_col = mark.end_col,
      hl_group = mark.hl,
      priority = mark.priority,
    })
  end
end

--- The columns a window has for text (without its number, sign and fold columns).
---@param win integer
function M.text_width(win)
  local info = vim.fn.getwininfo(win)[1]
  return info and info.width - info.textoff or vim.api.nvim_win_get_width(win)
end

--- Views laid out for their window's width (the statement, the sidebar, the results), by
--- buffer: drawn again when the width of the window showing them changes.
---@type table<integer, { redraw: fun(win: integer), width: integer? }>
local followers = {}

---@param buf integer
---@param redraw fun(win: integer)
function M.follow_width(buf, redraw)
  followers[buf] = { redraw = redraw, width = followers[buf] and followers[buf].width }
  local group = vim.api.nvim_create_augroup("programavimas_width", { clear = true })
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized", "BufWinEnter" }, {
    group = group,
    callback = vim.schedule_wrap(function()
      for view, follower in pairs(followers) do
        if not vim.api.nvim_buf_is_valid(view) then
          followers[view] = nil
        else
          local win = vim.fn.win_findbuf(view)[1]
          if win and follower.width and M.text_width(win) ~= follower.width then follower.redraw(win) end
        end
      end
    end),
  })
end

--- Records the width a followed view was drawn for.
---@param buf integer
---@param width integer
function M.drawn(buf, width)
  if followers[buf] then followers[buf].width = width end
end

--- The window showing `buf` in this tab page, if any.
---@param buf integer
---@return integer?
function M.window_of(buf)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == buf then return win end
  end
  return nil
end

---@class programavimas.Mark  A highlight, 0-based by byte columns
---@field line integer
---@field col integer
---@field end_col integer
---@field hl string
---@field priority integer?

---@class programavimas.Link  Where a link's text is, 0-based by byte columns
---@field line integer
---@field col integer
---@field end_col integer
---@field url string

--- A line builder that records highlights (and links) by byte columns as text is appended.
---@class programavimas.Lines
---@field lines string[]
---@field marks programavimas.Mark[]
---@field links programavimas.Link[]
local Lines = {}
Lines.__index = Lines

function M.lines()
  return setmetatable({ lines = {}, marks = {}, links = {}, current = nil }, Lines)
end

--- Appends a piece to the current line (starting one when needed). `hl` is a group or a list
--- of groups layered in order (a band below, a colour above it); `url` makes the piece a link.
---@param text string
---@param hl? string|string[]
---@param url? string
function Lines:add(text, hl, url)
  if self.current == nil then
    table.insert(self.lines, "")
    self.current = #self.lines
  end
  local line = self.lines[self.current]
  if hl and text ~= "" then
    local groups = type(hl) == "table" and hl or { hl }
    for layer, group in ipairs(groups) do
      table.insert(self.marks, {
        line = self.current - 1,
        col = #line,
        end_col = #line + #text,
        hl = group,
        priority = #groups > 1 and 4096 + layer or nil,
      })
    end
  end
  if url and text ~= "" then
    table.insert(self.links, { line = self.current - 1, col = #line, end_col = #line + #text, url = url })
  end
  self.lines[self.current] = line .. text
  return self
end

--- Ends the current line (an empty one when nothing was added).
function Lines:nl()
  if self.current == nil then table.insert(self.lines, "") end
  self.current = nil
  return self
end

--- A whole line.
---@param text string
---@param hl? string
function Lines:line(text, hl)
  return self:add(text, hl):nl()
end

--- Several lines of data, indented, each highlighted when `hl_of(index)` names a group.
---@param text string
---@param indent string
---@param hl_of? fun(index: integer): string?
function Lines:block(text, indent, hl_of)
  local normalised = text:gsub("\r\n?", "\n")
  if normalised:sub(-1) == "\n" then normalised = normalised:sub(1, -2) end
  local index = 0
  for piece in (normalised .. "\n"):gmatch("(.-)\n") do
    index = index + 1
    self:add(indent):add(piece, hl_of and hl_of(index) or nil):nl()
  end
  return self
end

--- The number of the line being built (1-based), for keys that act on lines.
function Lines:count() return #self.lines end

-- ------------------------------------------------------------------ wrapping

---@class programavimas.Segment  A piece of a line and its look
---@field text string
---@field hl string[]?
---@field url string?

---@param line programavimas.Segment[]
---@param text string
---@param segment programavimas.Segment
local function append(line, text, segment)
  local last = line[#line]
  if last and last.hl == segment.hl and last.url == segment.url then
    last.text = last.text .. text
  else
    table.insert(line, { text = text, hl = segment.hl, url = segment.url })
  end
end

--- Styled text as lines of at most `width` columns, broken at spaces (an `atomic` span, code
--- or a formula, only when it would not fit a line), `brk` spans and newlines kept.
---@param spans { text: string, hl: string[]?, url: string?, atomic: boolean?, brk: boolean? }[]
---@param width integer
---@return programavimas.Segment[][]
function M.wrap(spans, width)
  width = math.max(width, 4)
  local words, current, space = {}, nil, nil
  local function flush()
    if current then table.insert(words, current) end
    current = nil
  end
  local function push(text, span)
    if text == "" then return end
    if not current then
      current = { segments = {}, width = 0, space = space }
      space = nil
    end
    table.insert(current.segments, { text = text, hl = span.hl, url = span.url })
    current.width = current.width + vim.api.nvim_strwidth(text)
  end
  for _, span in ipairs(spans) do
    local text = span.text
    if span.brk then
      flush()
      space = nil
      table.insert(words, { brk = true })
    elseif span.atomic and vim.api.nvim_strwidth(text) <= width and not text:find("\n") then
      push(text, span)
    else
      local position = 1
      while position <= #text do
        local from, to = text:find("%s+", position)
        if not from then
          push(text:sub(position), span)
          break
        end
        if from > position then push(text:sub(position, from - 1), span) end
        flush()
        if text:sub(from, to):find("\n") then
          table.insert(words, { brk = true })
          space = nil
        else
          space = { text = " ", hl = span.hl, url = span.url }
        end
        position = to + 1
      end
    end
  end
  flush()

  local lines, line, used = {}, {}, 0
  local function newline()
    table.insert(lines, line)
    line, used = {}, 0
  end
  for _, word in ipairs(words) do
    if word.brk then
      newline()
    else
      if used > 0 and used + 1 + word.width > width then newline() end
      if used > 0 then
        local gap = word.space or { text = " " }
        append(line, " ", gap)
        used = used + 1
      end
      if word.width > width - used then
        -- Longer than a line (a long address): cut where the line ends.
        for _, segment in ipairs(word.segments) do
          for char in segment.text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            local cells = vim.api.nvim_strwidth(char)
            if used > 0 and used + cells > width then newline() end
            append(line, char, segment)
            used = used + cells
          end
        end
      else
        for _, segment in ipairs(word.segments) do append(line, segment.text, segment) end
        used = used + word.width
      end
    end
  end
  if #line > 0 or #lines == 0 then table.insert(lines, line) end
  return lines
end

---@param segments programavimas.Segment[]
function M.segments_width(segments)
  local total = 0
  for _, segment in ipairs(segments) do total = total + vim.api.nvim_strwidth(segment.text) end
  return total
end

return M
