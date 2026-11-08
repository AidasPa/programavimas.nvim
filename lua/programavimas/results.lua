-- Tests and results: a buffer below the editor, laid out like the VS Code extension's panel
-- (apps/vscode/src/views/results-model.ts): a meta line (problem · practice or graded · time),
-- the verdict as the title, chips, then the tests, each opening to its input, expected output
-- and the program's output with the differing lines marked. A judged submission shows every
-- test's data, hidden tests included (decided by the user); what is shown is exactly what the
-- server sent for the caller's own work.

local config = require("programavimas.config")
local diff = require("programavimas.diff")
local i18n = require("programavimas.i18n")
local ui = require("programavimas.ui")
local t = i18n.t

local M = {}

local BUFFER = "programavimas://results"

---@alias programavimas.ResultsState
---| { kind: "idle" }
---| { kind: "sending", graded: boolean, input?: "samples"|"custom", title: string }
---| { kind: "status", status: table, title: string }
---| { kind: "error", title: string, message: string }

---@class programavimas.ResultsContext
---@field started_at number?
---@field attempts { left: integer, total: integer? }?
---@field open table<integer, boolean>  Tests opened or closed by the student, by position

M.state = { kind = "idle" } ---@type programavimas.ResultsState
M.context = { open = {} } ---@type programavimas.ResultsContext
--- Line (1-based) → test position, and whether each test shows its data, for <CR>.
local line_tests, shown_open = {}, {}

local function megabytes(bytes)
  return (("%.1f"):format(bytes / 1048576):gsub("%.0$", ""))
end

---@param tests table[]
local function chosen_test(tests)
  local function failing(test) return test.verdict ~= nil and test.verdict ~= "accepted" end
  for _, test in ipairs(tests) do
    if failing(test) and not test.dataHidden then return test end
  end
  for _, test in ipairs(tests) do
    if failing(test) then return test end
  end
  return nil
end

---@param out programavimas.Lines
---@param label string
---@param text string
---@param marks boolean[]?
---@param hl string?
local function data_block(out, label, text, marks, hl)
  out:line("    " .. label, "ProgramavimasHeading")
  local lines = diff.output_lines(text)
  if #lines == 0 then
    out:line("      " .. t("results.empty"), "ProgramavimasMuted")
    return
  end
  for index, line in ipairs(lines) do
    out:add(("%6d  "):format(index), "ProgramavimasFaint")
    out:add(line, marks and marks[index] and hl or nil):nl()
  end
end

---@param out programavimas.Lines
---@param first programavimas.FirstDifference?
local function caption(out, first)
  if not first then return end
  local text
  if first.expected == nil then
    text = t("results.extraLine", { line = first.line, actual = diff.clip(first.actual or "") })
  elseif first.actual == nil then
    text = t("results.missingLine", { line = first.line, expected = diff.clip(first.expected) })
  else
    text = t("results.firstDifference", {
      line = first.line,
      expected = diff.clip(first.expected),
      actual = diff.clip(first.actual),
    })
  end
  out:line("    " .. text, "ProgramavimasMuted")
end

---@param out programavimas.Lines
---@param test table
local function test_detail(out, test)
  if test.dataHidden then
    out:line("    " .. t("results.hidden"), "ProgramavimasMuted")
    return
  end
  local marks = test.expected and test.actual and diff.compare(test.expected, test.actual) or nil
  if test.input then data_block(out, t("results.input"), test.input) end
  if test.expected then data_block(out, t("results.expected"), test.expected, marks and marks.expected, "ProgramavimasDiff") end
  if test.actual then data_block(out, t("results.actual"), test.actual, marks and marks.actual, "ProgramavimasDiff") end
  caption(out, marks and marks.first)
  if test.stderr and test.stderr ~= "" then data_block(out, t("results.stderr"), test.stderr) end
  if test.checkerMessage and test.checkerMessage ~= "" then
    data_block(out, t("results.checker"), test.checkerMessage)
  end
  if test.truncated then out:line("    " .. t("results.truncated"), "ProgramavimasMuted") end
end

---@param out programavimas.Lines
---@param tests table[]
---@param title string
local function tests_section(out, tests, title)
  if #tests == 0 then return end
  local chosen = chosen_test(tests)
  out:nl():line(title, "ProgramavimasTitle")
  local names, labels = {}, {}
  local name_width, label_width = 0, 0
  for index, test in ipairs(tests) do
    names[index] = t(test.sample and "results.sample" or "results.test", { number = test.position })
    labels[index] = test.verdict and t("verdict." .. test.verdict) or t("results.notRun")
    name_width = math.max(name_width, vim.fn.strdisplaywidth(names[index]))
    label_width = math.max(label_width, vim.fn.strdisplaywidth(labels[index]))
  end
  local icons = config.options.icons
  for index, test in ipairs(tests) do
    local open = M.context.open[test.position]
    if open == nil then open = test == chosen end
    local glyph = test.verdict and ui.verdict_glyph(test.verdict)
      or { icon = icons.not_started, hl = "ProgramavimasMuted" }
    local pad = function(text, width) return text .. (" "):rep(width - vim.fn.strdisplaywidth(text)) end
    out:add((open and icons.expanded or icons.collapsed) .. " ", "ProgramavimasMuted")
    out:add(glyph.icon, glyph.hl):add(" " .. pad(names[index], name_width) .. "  ")
    out:add(pad(labels[index], label_width), test.verdict and test.verdict ~= "accepted" and glyph.hl or nil)
    out:add("  " .. (test.timeMs and t("results.time", { ms = test.timeMs }) or "—"), "ProgramavimasMuted")
    out:add("  " .. (test.memoryBytes and t("results.memory", { mb = megabytes(test.memoryBytes) }) or "—"), "ProgramavimasMuted")
    out:nl()
    line_tests[out:count()] = test.position
    shown_open[test.position] = open
    if open then test_detail(out, test) end
  end
end

---@param out programavimas.Lines
---@param general table[]?
local function general_messages(out, general)
  if not general or #general == 0 then return end
  out:nl():line(t("results.general"), "ProgramavimasTitle")
  for _, message in ipairs(general) do
    local hl = message.severity == "error" and "ProgramavimasDanger" or "ProgramavimasMuted"
    out:block(message.message, "  ", function() return hl end)
  end
end

---@param chips { text: string, hl: string? }[]
---@param out programavimas.Lines
local function chip_line(out, chips)
  if #chips == 0 then return end
  for index, chip in ipairs(chips) do
    if index > 1 then out:add(" · ", "ProgramavimasFaint") end
    out:add(chip.text, chip.hl or "ProgramavimasMuted")
  end
  out:nl()
end

--- A progress bar of 24 cells; nil total shows an indeterminate one.
---@param done integer?
---@param total integer?
---@param out programavimas.Lines
local function progress_bar(out, done, total)
  local width = 24
  local filled
  if total and total > 0 then
    filled = math.floor(width * math.min(done or 0, total) / total + 0.5)
  else
    local position = math.floor(vim.uv.now() / 80) % width
    out:add(("─"):rep(position), "ProgramavimasFaint"):add("━━━", "ProgramavimasProgress")
    out:add(("─"):rep(math.max(0, width - position - 3)), "ProgramavimasFaint"):nl()
    return
  end
  out:add(("━"):rep(filled), "ProgramavimasProgress"):add(("─"):rep(width - filled), "ProgramavimasFaint"):nl()
end

---@param state programavimas.ResultsState
---@return boolean? graded
local function graded_of(state)
  if state.kind == "sending" then return state.graded end
  if state.kind == "status" then return state.status.kind == "judgement" end
  return nil
end

--- The whole view as lines and highlights. Pure apart from the spinner's frame.
---@param state programavimas.ResultsState
---@param context programavimas.ResultsContext
---@return programavimas.Lines
function M.build(state, context)
  line_tests, shown_open = {}, {}
  local out = ui.lines()
  if state.kind == "idle" then
    out:line(t("results.idleTitle"), "ProgramavimasTitle")
    out:line(t("results.idleBody"), "ProgramavimasMuted")
    return out
  end

  -- Problem · mode · time
  out:add(state.title, "ProgramavimasMuted")
  local graded = graded_of(state)
  if graded ~= nil then out:add(" · " .. t(graded and "mode.graded" or "mode.practice"), "ProgramavimasMuted") end
  if context.started_at then
    out:add(" · " .. require("programavimas.time").clock(context.started_at), "ProgramavimasMuted")
  end
  out:nl()

  if state.kind == "sending" then
    out:add(ui.spinner() .. " ", "ProgramavimasProgress"):line(t("judging.sending"), "ProgramavimasTitle")
    progress_bar(out, nil, nil)
    return out
  end
  if state.kind == "error" then
    out:line(t("results.refusedTitle"), "ProgramavimasTitle")
    out:line(state.message, "ProgramavimasDanger")
    return out
  end

  local status = state.status
  local result = status.result
  local finished = status.phase == "finished" and result ~= nil
  if not finished then
    local glyph = ui.run_glyph(status.phase, nil)
    out:add(glyph.icon .. " ", glyph.hl):add(t("judging." .. status.phase), "ProgramavimasTitle")
    local progress = status.phase == "testing" and status.progress or nil
    if progress then out:add(("  %d/%d"):format(progress.done, progress.total), "ProgramavimasMuted") end
    out:nl()
    if ui.running(status.phase) then
      progress_bar(out, progress and progress.done, progress and progress.total)
    elseif status.phase == "cancelled" then
      out:line(t("results.cancelled"), "ProgramavimasMuted")
    elseif status.phase == "failed" then
      out:line(t(status.kind == "judgement" and "results.busyGraded" or "results.systemPractice"), "ProgramavimasMuted")
    end
    return out
  end

  if status.kind == "practice" then
    if result.failure then
      out:add(ui.run_glyph("failed", nil).icon .. " ", "ProgramavimasMuted"):line(t("judging.failed"), "ProgramavimasTitle")
      out:line(t(result.failure == "busy" and "results.busyPractice" or "results.systemPractice"), "ProgramavimasMuted")
      return out
    end
    if status.input == "custom" and result.output then
      local output = result.output
      if result.verdict then
        local glyph = ui.verdict_glyph(result.verdict)
        out:add(glyph.icon .. " ", glyph.hl):line(glyph.label, "ProgramavimasTitle")
      else
        out:line(t("results.customOutput"), "ProgramavimasTitle")
      end
      local chips = {}
      if output.timeMs then table.insert(chips, { text = t("results.time", { ms = output.timeMs }) }) end
      if output.memoryBytes then
        table.insert(chips, { text = t("results.memory", { mb = megabytes(output.memoryBytes) }) })
      end
      chip_line(out, chips)
      out:nl():line(t("results.customTitle"), "ProgramavimasTitle")
      if output.stdout ~= "" or not output.outputFile then
        data_block(out, t("results.customOutput"), output.stdout)
      end
      if output.outputFile then data_block(out, vim.trim(t("results.outputFile", { name = "" })), output.outputFile) end
      if output.stderr ~= "" then data_block(out, t("results.stderr"), output.stderr) end
      if output.truncated then out:line("    " .. t("results.truncated"), "ProgramavimasMuted") end
    else
      local tests = result.tests or {}
      local passed = #vim.tbl_filter(function(test) return test.verdict == "accepted" end, tests)
      if result.verdict then
        local glyph = ui.verdict_glyph(result.verdict)
        out:add(glyph.icon .. " ", glyph.hl):line(glyph.label, "ProgramavimasTitle")
      else
        out:line(t("judging.finished"), "ProgramavimasTitle")
      end
      if #tests > 0 then
        local max_time, max_memory = nil, nil
        for _, test in ipairs(tests) do
          if test.timeMs then max_time = math.max(max_time or 0, test.timeMs) end
          if test.memoryBytes then max_memory = math.max(max_memory or 0, test.memoryBytes) end
        end
        local chips = { {
          text = t("results.samplesPassed", { passed = passed, total = #tests }),
          hl = passed == #tests and "ProgramavimasSuccess" or "ProgramavimasProgress",
        } }
        if max_time then table.insert(chips, { text = t("results.maxTime", { ms = max_time }) }) end
        if max_memory then table.insert(chips, { text = t("results.maxMemory", { mb = megabytes(max_memory) }) }) end
        chip_line(out, chips)
      end
      tests_section(out, tests, t("results.samplesTitle"))
    end
    if #(result.diagnostics or {}) > 0 then out:nl():line(t("results.compilerMessages"), "ProgramavimasMuted") end
    general_messages(out, result.general)
    return out
  end

  -- A graded submission.
  local submission = result.submission
  local tests = result.tests or {}
  local passed = #vim.tbl_filter(function(test) return test.verdict == "accepted" end, tests)
  if submission.verdict then
    local glyph = ui.verdict_glyph(submission.verdict)
    out:add(glyph.icon .. " ", glyph.hl):line(glyph.label, "ProgramavimasTitle")
  else
    out:line(t("judging." .. submission.state), "ProgramavimasTitle")
  end
  local chips = {}
  if #tests > 0 then
    table.insert(chips, {
      text = t("results.testsChip", { passed = passed, total = #tests }),
      hl = passed == #tests and "ProgramavimasSuccess" or "ProgramavimasProgress",
    })
  end
  if submission.score ~= nil and submission.maxScore ~= nil then
    table.insert(chips, { text = t("results.points", { score = submission.score, max = submission.maxScore }) })
  end
  local attempts = context.attempts
  if attempts and attempts.total then
    table.insert(chips, { text = t("attempts.short", { left = attempts.left, total = attempts.total }) })
  end
  chip_line(out, chips)
  local hidden = vim.iter(tests):any(function(test) return test.dataHidden and test.verdict ~= "accepted" end)
  if hidden then
    local note = result.firstFailedTest
        and t("results.firstFailure", { number = result.firstFailedTest }) .. " · " .. t("results.hidden")
      or t("results.hidden")
    out:line(note, "ProgramavimasMuted")
  end
  tests_section(out, tests, t("results.testsTitle"))
  if #(result.diagnostics or {}) > 0 then out:nl():line(t("results.compilerMessages"), "ProgramavimasMuted") end
  general_messages(out, result.general)
  return out
end

-- ------------------------------------------------------------------ the view

local function buffer()
  local buf = ui.scratch(BUFFER, "programavimas-results")
  if not vim.b[buf].programavimas_keys then
    vim.b[buf].programavimas_keys = true
    local function map(lhs, fn, desc)
      vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
    end
    map("<CR>", function()
      local position = line_tests[vim.api.nvim_win_get_cursor(0)[1]]
      if not position then return end
      M.context.open[position] = not shown_open[position]
      M.redraw()
    end, "Show or hide the test")
    map("q", function() M.close() end, "Close")
    map("r", function() require("programavimas.judge").start("samples") end, "Run samples")
    map("?", function() ui.notify(t("results.help")) end, "Help")
  end
  return buf
end

function M.redraw()
  local buf = vim.fn.bufnr(BUFFER)
  if buf == -1 then return end
  local out = M.build(M.state, M.context)
  ui.render(buf, out.lines, out.marks)
end

--- Shows the view (keeping the cursor where it was).
function M.show()
  local buf = buffer()
  M.redraw()
  if ui.window_of(buf) then return end
  local current = vim.api.nvim_get_current_win()
  vim.cmd(("botright %dsplit"):format(config.options.results.height))
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].wrap = false
  vim.wo[win].winfixheight = true
  vim.wo[win].cursorline = true
  if vim.api.nvim_win_is_valid(current) then vim.api.nvim_set_current_win(current) end
end

function M.close()
  local buf = vim.fn.bufnr(BUFFER)
  local win = buf ~= -1 and ui.window_of(buf) or nil
  if win and #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.api.nvim_win_close(win, false) end
end

function M.toggle()
  local buf = vim.fn.bufnr(BUFFER)
  if buf ~= -1 and ui.window_of(buf) then M.close() else M.show() end
end

--- A newer status of the same run: redrawn where it is shown, never reopened.
---@param state programavimas.ResultsState
function M.update(state)
  M.state = state
  M.redraw()
end

--- A new state, shown; `fresh` starts a new run (the opened tests and the clock reset).
---@param state programavimas.ResultsState
---@param fresh? boolean
---@param attempts? { left: integer, total: integer? }
function M.set(state, fresh, attempts)
  if fresh then M.context = { open = {}, started_at = os.time() } end
  if attempts then M.context.attempts = attempts end
  M.state = state
  M.show()
end

return M
