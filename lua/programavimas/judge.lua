-- Runs and submissions of the current solution. Code never runs on this computer: it goes to
-- the judge on the server. Neovim has no TLS sockets, so the run's status is followed by
-- reading it (`GET /runs/{id}`, `GET /submissions/{id}`) at most once a second until it ends
-- (docs/public-api.md §2, "Live status"); the server answers those reads from its cache.
-- Compiler messages become diagnostics on the main file and clear on the next edit.

local api = require("programavimas.api")
local async = require("programavimas.async")
local config = require("programavimas.config")
local i18n = require("programavimas.i18n")
local paths = require("programavimas.paths")
local problems = require("programavimas.problems")
local results = require("programavimas.results")
local ui = require("programavimas.ui")
local t = i18n.t

local M = {}

local POLL_MS = { 600, 1000 } -- the first read soon, then once a second
local GIVE_UP_MS = 10 * 60 * 1000

--- The run being followed (a newer one replaces it), and the last outcome per problem.
---@type { generation: integer, key: string, phase: string, progress: table?, graded: boolean }?
M.active = nil
---@type table<string, { verdict: string?, phase: string }>
M.last = {}
local generation = 0
local spinner ---@type uv.uv_timer_t?

local function key_of(marker) return marker.courseId .. "|" .. marker.problemId end

local function tick()
  if not M.active then
    if spinner then
      spinner:stop()
      spinner:close()
      spinner = nil
    end
    return
  end
  if results.state.kind == "sending" or (results.state.kind == "status" and ui.running(results.state.status.phase)) then
    results.redraw()
  end
  vim.cmd.redrawstatus()
end

local function start_spinner()
  if spinner then return end
  spinner = vim.uv.new_timer()
  spinner:start(100, 100, vim.schedule_wrap(tick))
end

-- ------------------------------------------------------------------ diagnostics

---@param buf integer
---@param result table?  The practice result or the judgement's result
---@param language string
local function set_diagnostics(buf, result, language)
  vim.diagnostic.reset(ui.ns, buf)
  local items = result and result.diagnostics or {}
  if #items == 0 or not vim.api.nvim_buf_is_valid(buf) then return end
  local severity = {
    error = vim.diagnostic.severity.ERROR,
    warning = vim.diagnostic.severity.WARN,
    note = vim.diagnostic.severity.INFO,
  }
  local line_count = vim.api.nvim_buf_line_count(buf)
  vim.diagnostic.set(ui.ns, buf, vim.tbl_map(function(item)
    local lnum = math.min(item.startLine, line_count) - 1
    local end_lnum = math.max(lnum, math.min(item.endLine, line_count) - 1)
    return {
      lnum = lnum,
      col = item.startColumn - 1,
      end_lnum = end_lnum,
      end_col = item.endColumn - 1,
      severity = severity[item.severity] or vim.diagnostic.severity.ERROR,
      message = item.message,
      source = paths.LANGUAGES[language] and paths.LANGUAGES[language].compiler or "judge",
    }
  end, items))
  -- They describe the code as it was sent: the next edit clears them.
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    buffer = buf,
    once = true,
    callback = function() vim.diagnostic.reset(ui.ns, buf) end,
  })
end

-- ------------------------------------------------------------------ running

---@param solution programavimas.Solution
---@return integer buf, string source
local function source_of(solution)
  local buf = vim.fn.bufnr(solution.main)
  if buf == -1 then
    buf = vim.fn.bufadd(solution.main)
    vim.fn.bufload(buf)
  end
  if config.options.save_before_run and vim.bo[buf].modified then
    vim.api.nvim_buf_call(buf, function() vim.cmd("silent update") end)
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local source = table.concat(lines, "\n")
  if vim.bo[buf].eol and #lines > 0 then source = source .. "\n" end
  return buf, source
end

---@param folder string
---@param name string
local function custom_input(folder, name)
  local path = vim.fs.joinpath(folder, name)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    return table.concat(lines, "\n") .. (vim.bo[buf].eol and "\n" or ""), path
  end
  local file = io.open(path, "rb")
  if not file then return nil, path end
  local text = file:read("*a")
  file:close()
  return text, path
end

---@param status table  A practice or judgement status
local function finished(status) return not ui.running(status.phase) end

--- The words for a finished run, for the notification.
---@param status table
local function outcome(status)
  local result = status.result
  if status.phase ~= "finished" or not result then
    return t("judging." .. status.phase), vim.log.levels.WARN
  end
  local verdict = status.kind == "judgement" and result.submission.verdict or result.verdict
  if not verdict then return t("judging.finished"), vim.log.levels.INFO end
  local tests = result.tests or {}
  local passed = #vim.tbl_filter(function(test) return test.verdict == "accepted" end, tests)
  local text = t("verdict." .. verdict)
  if #tests > 0 then
    text = text .. " · " .. t(status.kind == "judgement" and "results.testsChip" or "results.samplesPassed", {
      passed = passed,
      total = #tests,
    })
  end
  return text, verdict == "accepted" and vim.log.levels.INFO or vim.log.levels.WARN
end

--- Starts a run of the current solution: "samples", "custom" or "submit" (graded).
---@param kind "samples"|"custom"|"submit"
function M.start(kind)
  local solution = require("programavimas.solutions").solution_for(vim.api.nvim_buf_get_name(0))
  -- From the results or statement buffer: the solution of the last run.
  if not solution and M.solution and vim.uv.fs_stat(M.solution.main) then solution = M.solution end
  if not solution then return ui.warn(t("open.notSolution")) end
  M.solution = solution
  async.run(function()
    local marker = solution.marker
    require("programavimas.account").load() -- the account's language for the messages
    local detail, err = problems.detail(marker.courseId, marker.problemId)
    if not detail then return ui.error(ui.api_message(err)) end
    if kind == "samples" and #(detail.samples or {}) == 0 then return ui.warn(t("errors.noSamples")) end
    local buf, source = source_of(solution)
    local request = { language = solution.language, source = source }
    local custom ---@type programavimas.CustomInput?
    if kind ~= "submit" then
      request.input = { kind = "samples" }
      if kind == "custom" then
        local name = paths.custom_input_name(detail.io)
        local stdin, path = custom_input(solution.folder, name)
        if not stdin then
          ui.notify(t("open.customInput", { file = name }))
          return vim.cmd.edit(vim.fn.fnameescape(path))
        end
        request.input = { kind = "custom", stdin = stdin }
        custom = { file = name, output = detail.io.kind == "files" and detail.io.output or nil, text = stdin }
      end
    end

    generation = generation + 1
    local mine = generation
    local key = key_of(marker)
    local graded = kind == "submit"
    local title = detail.title
    M.active = { generation = mine, key = key, phase = "queued", graded = graded }
    start_spinner()
    results.set(
      { kind = "sending", graded = graded, input = request.input and request.input.kind, title = title },
      true,
      detail.attempts,
      custom
    )

    local response, refusal
    if graded then
      response, refusal = api.submit(marker.courseId, marker.problemId, request)
    else
      response, refusal = api.run(marker.courseId, marker.problemId, request)
    end
    if generation ~= mine then return end
    if not response then
      M.active = nil
      local message = refusal.kind == "refused" and ui.refusal_message(refusal) or ui.api_message(refusal)
      results.update({ kind = "error", title = title, message = message })
      return ui.warn(message)
    end

    local status = graded and response.judgement or response
    local read = graded
        and function()
          local submission, read_err = api.get_submission(response.id)
          return submission and submission.judgement, read_err
        end
      or function() return api.get_run(response.id) end
    local started = vim.uv.now()
    local polls = 0
    while true do
      if generation ~= mine then return end
      M.active.phase, M.active.progress = status.phase, status.progress
      results.update({ kind = "status", status = status, title = title })
      if finished(status) then break end
      if vim.uv.now() - started > GIVE_UP_MS then
        M.active = nil
        results.update({ kind = "error", title = title, message = t("results.lost") })
        return
      end
      polls = polls + 1
      async.sleep(POLL_MS[math.min(polls, #POLL_MS)])
      local next_status, read_err = read()
      if generation ~= mine then return end
      if next_status then
        status = next_status
      elseif read_err and read_err.kind ~= "network" then
        M.active = nil
        results.update({ kind = "error", title = title, message = t("results.lost") })
        return ui.warn(ui.api_message(read_err))
      end
    end

    M.active = nil
    local result = status.result
    local verdict = result and (graded and result.submission.verdict or result.verdict) or nil
    M.last[key] = { verdict = verdict, phase = status.phase }
    set_diagnostics(buf, result, solution.language)
    local text, level = outcome(status)
    ui.notify(title .. ": " .. text, level)
    vim.cmd.redrawstatus()
    -- The problem's status and attempts changed: its statement, the sidebar and the chips.
    local fresh = problems.detail(marker.courseId, marker.problemId, true)
    if fresh then
      require("programavimas.statement").update(fresh)
      require("programavimas.courses").update_status(marker.courseId, marker.problemId, fresh.status)
      if graded then
        results.context.attempts = fresh.attempts
        results.redraw()
      end
    end
  end)
end

--- The caller's recent submissions in a picker; the chosen one opens in the results view.
function M.pick_submission()
  async.run(function()
    local page, err = api.submissions({ limit = 30 })
    if not page then return ui.error(ui.api_message(err)) end
    if #(page.items or {}) == 0 then return ui.notify(t("submissions.empty")) end
    local time = require("programavimas.time")
    local choice = async.await(function(done)
      vim.ui.select(page.items, {
        prompt = t("submissions.prompt"),
        format_item = function(item)
          local glyph = ui.run_glyph(item.state, item.verdict)
          local at = time.parse(item.submittedAt)
          return ("%s %s · %s · %s · %s"):format(
            glyph.icon,
            item.problemTitle,
            glyph.label,
            item.language.name,
            at and time.date_time(at) or ""
          )
        end,
      }, done)
    end)
    if not choice then return end
    local submission, read_err = api.get_submission(choice.id)
    if not submission then return ui.error(ui.api_message(read_err)) end
    results.set({ kind = "status", status = submission.judgement, title = submission.problemTitle }, true)
  end)
end

--- Forgets everything about the signed-out account.
function M.forget()
  generation = generation + 1
  M.active = nil
  M.last = {}
  M.solution = nil
  problems.details = {}
  results.context = { open = {} }
  results.update({ kind = "idle" })
  results.close()
end

-- ------------------------------------------------------------------ the status line

--- "Course · Problem · ⠋ Testing 7/12 · Attempts left: 3 of 5" for the current solution
--- buffer, empty elsewhere. For statusline plugins: `require("programavimas").statusline()`.
function M.statusline()
  local ok, solution = pcall(require("programavimas.solutions").solution_for, vim.api.nvim_buf_get_name(0))
  if not ok or not solution then return "" end
  local marker = solution.marker
  local key = key_of(marker)
  local detail = problems.details[key]
  local parts = {}
  if detail then
    table.insert(parts, detail.title)
  end
  local active = M.active and M.active.key == key and M.active or nil
  if active then
    local step = t("judging." .. active.phase)
    if active.phase == "testing" and active.progress then
      step = step .. (" %d/%d"):format(active.progress.done, active.progress.total)
    end
    table.insert(parts, ui.spinner() .. " " .. step)
  elseif M.last[key] then
    local last = M.last[key]
    local glyph = ui.run_glyph(last.phase, last.verdict)
    table.insert(parts, glyph.icon .. " " .. glyph.label)
  end
  if detail and detail.attempts and detail.attempts.total then
    table.insert(parts, ("%d/%d"):format(detail.attempts.left, detail.attempts.total))
  end
  local file = (paths.LANGUAGES[solution.language] or {}).file
  local synced = require("programavimas.drafts").statusline(vim.api.nvim_get_current_buf())
  table.insert(parts, synced and file .. " " .. synced or file)
  return table.concat(parts, " · ")
end

return M
