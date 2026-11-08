-- Tests and results: a buffer below the editor, laid out like the VS Code extension's panel
-- (apps/vscode/src/views/results-model.ts): a meta line (problem · practice or graded · time),
-- the verdict as the title, chips, then the tests, each opening to its input, expected output
-- and the program's output with the differing lines marked. A judged submission shows every
-- test's data, hidden tests included (decided by the user); what is shown is exactly what the
-- server sent for the caller's own work. A run with custom input shows that input beside the
-- program's output.

local config = require("programavimas.config")
local diff = require("programavimas.diff")
local i18n = require("programavimas.i18n")
local ui = require("programavimas.ui")
local t = i18n.t

local M = {}

local BUFFER = "programavimas://results"
-- Data sits under its test's name, its blocks side by side when the window is wide enough.
local INDENT = "    "
local GAP = 4

---@alias programavimas.ResultsState
---| { kind: "idle" }
---| { kind: "sending", graded: boolean, input?: "samples"|"custom", title: string }
---| { kind: "status", status: table, title: string }
---| { kind: "error", title: string, message: string }

---@class programavimas.CustomInput  What a run with custom input was given
---@field file string    The input file it came from (input.txt, duom.txt)
---@field output string? The problem's output file, when it writes one
---@field text string

---@class programavimas.ResultsContext
---@field started_at number?
---@field attempts { left: integer, total: integer? }?
---@field open table<integer, boolean>  Tests opened or closed by the student, by position
---@field custom programavimas.CustomInput?

M.state = { kind = "idle" } ---@type programavimas.ResultsState
M.context = { open = {} } ---@type programavimas.ResultsContext
--- Line (1-based) → test position, and whether each test shows its data, for <CR>.
local line_tests, shown_open = {}, {}

local function megabytes(bytes) return i18n.number(bytes / 1048576) end

local width_of = vim.api.nvim_strwidth

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

-- ------------------------------------------------------------------ data blocks

---@class programavimas.DataBlock
---@field label string
---@field text string
---@field marks boolean[]?  Lines that differ
---@field hl string?

--- A block's rows (its label, then its lines numbered; differing lines marked across the
--- block's width) and that width.
---@param block programavimas.DataBlock
---@return { [1]: string, [2]: string? }[][] rows, integer width
local function block_rows(block)
  local rows = { { { block.label, "ProgramavimasMuted" } } }
  local lines = diff.output_lines(block.text)
  if #lines == 0 then
    local empty = " " .. t("results.empty")
    table.insert(rows, { { empty, "ProgramavimasFaint" } })
    return rows, math.max(width_of(block.label), width_of(empty))
  end
  local digits = #tostring(#lines)
  local text_width = 0
  for _, line in ipairs(lines) do text_width = math.max(text_width, width_of(line)) end
  for index, line in ipairs(lines) do
    local marked = block.marks and block.marks[index]
    table.insert(rows, {
      { ("%" .. (digits + 1) .. "d  "):format(index), "ProgramavimasFaint" },
      { marked and line .. (" "):rep(text_width - width_of(line)) or line, marked and block.hl or nil },
    })
  end
  return rows, math.max(width_of(block.label), digits + 3 + text_width)
end

---@param out programavimas.Lines
---@param row { [1]: string, [2]: string? }[]
---@return integer width
local function row_out(out, row)
  local used = 0
  for _, piece in ipairs(row) do
    out:add(piece[1], piece[2])
    used = used + width_of(piece[1])
  end
  return used
end

--- Whether blocks fit side by side in `width` columns.
---@param width integer
---@param blocks programavimas.DataBlock[]
local function fit(width, blocks)
  local total = #INDENT - GAP
  for _, block in ipairs(blocks) do total = total + select(2, block_rows(block)) + GAP end
  return total <= width
end

--- Blocks side by side when they fit the width, else one under another.
---@param out programavimas.Lines
---@param width integer
---@param blocks programavimas.DataBlock[]
local function blocks_out(out, width, blocks)
  local columns, height = {}, 0
  for index, block in ipairs(blocks) do
    local rows, cells = block_rows(block)
    columns[index] = { rows = rows, width = cells }
    height = math.max(height, #rows)
  end
  if #blocks > 1 and fit(width, blocks) then
    for index = 1, height do
      out:add(INDENT)
      local position, start = 0, 0
      for _, column in ipairs(columns) do
        if column.rows[index] then
          out:add((" "):rep(start - position))
          position = start + row_out(out, column.rows[index])
        end
        start = start + column.width + GAP
      end
      out:nl()
    end
    return
  end
  for _, column in ipairs(columns) do
    for _, row in ipairs(column.rows) do
      out:add(INDENT)
      row_out(out, row)
      out:nl()
    end
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
  out:add(INDENT):line(text, "ProgramavimasWarning")
end

---@param out programavimas.Lines
---@param test table
---@param width integer
local function test_detail(out, test, width)
  if test.dataHidden then
    out:add(INDENT):line(t("results.hidden"), "ProgramavimasMuted")
    return
  end
  local marks = test.expected and test.actual and diff.compare(test.expected, test.actual) or nil
  local input = test.input and { label = t("results.input"), text = test.input }
  local outputs = {}
  if test.expected then
    table.insert(outputs, { label = t("results.expected"), text = test.expected, marks = marks and marks.expected, hl = "ProgramavimasDiff" })
  end
  if test.actual then
    table.insert(outputs, { label = t("results.actual"), text = test.actual, marks = marks and marks.actual, hl = "ProgramavimasDiff" })
  end
  -- Input, expected and actual in one row when the window is wide enough; else the input,
  -- then the two outputs side by side for comparing.
  local all = vim.list_extend(input and { input } or {}, outputs)
  if fit(width, all) then
    blocks_out(out, width, all)
  else
    if input then blocks_out(out, width, { input }) end
    blocks_out(out, width, outputs)
  end
  caption(out, marks and marks.first)
  if test.stderr and test.stderr ~= "" then blocks_out(out, width, { { label = t("results.stderr"), text = test.stderr } }) end
  if test.checkerMessage and test.checkerMessage ~= "" then
    blocks_out(out, width, { { label = t("results.checker"), text = test.checkerMessage } })
  end
  if test.truncated then out:add(INDENT):line(t("results.truncated"), "ProgramavimasMuted") end
end

--- The tests in aligned columns (name, verdict, time and memory right-aligned), each opening
--- to its data with <CR>.
---@param out programavimas.Lines
---@param tests table[]
---@param title string
---@param width integer
local function tests_section(out, tests, title, width)
  if #tests == 0 then return end
  local chosen = chosen_test(tests)
  out:nl():line(title, "ProgramavimasTitle")
  local columns = { {}, {}, {}, {} }
  local widths = { 0, 0, 0, 0 }
  for index, test in ipairs(tests) do
    columns[1][index] = t(test.sample and "results.sample" or "results.test", { number = test.position })
    columns[2][index] = test.verdict and t("verdict." .. test.verdict) or t("results.notRun")
    columns[3][index] = test.timeMs and t("results.time", { ms = test.timeMs }) or "—"
    columns[4][index] = test.memoryBytes and t("results.memory", { mb = megabytes(test.memoryBytes) }) or "—"
    for column = 1, 4 do widths[column] = math.max(widths[column], width_of(columns[column][index])) end
  end
  local function left(column, index)
    local text = columns[column][index]
    return text .. (" "):rep(widths[column] - width_of(text))
  end
  local function right(column, index)
    local text = columns[column][index]
    return (" "):rep(widths[column] - width_of(text)) .. text
  end
  local icons = config.options.icons
  for index, test in ipairs(tests) do
    local open = M.context.open[test.position]
    if open == nil then open = test == chosen end
    local glyph = test.verdict and ui.verdict_glyph(test.verdict)
      or { icon = icons.not_started, hl = "ProgramavimasMuted" }
    out:add((open and icons.expanded or icons.collapsed) .. " ", "ProgramavimasMuted")
    out:add(glyph.icon, glyph.hl):add(" " .. left(1, index) .. "   ")
    out:add(left(2, index), test.verdict and test.verdict ~= "accepted" and glyph.hl or nil)
    out:add("   " .. right(3, index) .. "   " .. right(4, index), "ProgramavimasMuted")
    out:nl()
    line_tests[out:count()] = test.position
    shown_open[test.position] = open
    if open then test_detail(out, test, width) end
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

--- A finished run's verdict as the title, or `fallback` without one.
---@param out programavimas.Lines
---@param verdict string?
---@param fallback string
local function verdict_title(out, verdict, fallback)
  if verdict then
    local glyph = ui.verdict_glyph(verdict)
    out:add(glyph.icon .. " ", glyph.hl):line(glyph.label, "ProgramavimasTitle")
  else
    out:line(fallback, "ProgramavimasTitle")
  end
end

--- A run with custom input: the input it was given beside what the program wrote.
---@param out programavimas.Lines
---@param output table
---@param custom programavimas.CustomInput?
---@param width integer
local function custom_section(out, output, custom, width)
  out:nl():line(t("results.customTitle"), "ProgramavimasTitle")
  local input = custom and { label = t("results.inputFrom", { file = custom.file }), text = custom.text } or nil
  local written = {}
  if output.stdout ~= "" or not output.outputFile then
    table.insert(written, { label = t("results.customOutput"), text = output.stdout })
  end
  if output.outputFile then
    local name = custom and custom.output or ""
    table.insert(written, { label = vim.trim(t("results.outputFile", { name = name })), text = output.outputFile })
  end
  local all = vim.list_extend(input and { input } or {}, written)
  if fit(width, all) then
    blocks_out(out, width, all)
  else
    for _, block in ipairs(all) do blocks_out(out, width, { block }) end
  end
  if output.stderr ~= "" then blocks_out(out, width, { { label = t("results.stderr"), text = output.stderr } }) end
  if output.truncated then out:add(INDENT):line(t("results.truncated"), "ProgramavimasMuted") end
end

--- The whole view as lines and highlights, for a window `width` columns wide. Pure apart from
--- the spinner's frame.
---@param state programavimas.ResultsState
---@param context programavimas.ResultsContext
---@param width? integer
---@return programavimas.Lines
function M.build(state, context, width)
  width = width or 100
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
  if graded ~= nil then
    out:add(" · ", "ProgramavimasFaint"):add(t(graded and "mode.graded" or "mode.practice"), "ProgramavimasMuted")
  end
  if context.started_at then
    out:add(" · ", "ProgramavimasFaint"):add(require("programavimas.time").clock(context.started_at), "ProgramavimasMuted")
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

  local tests = result.tests or {}
  local passed = #vim.tbl_filter(function(test) return test.verdict == "accepted" end, tests)
  if status.kind == "practice" then
    if result.failure then
      out:add(ui.run_glyph("failed", nil).icon .. " ", "ProgramavimasMuted"):line(t("judging.failed"), "ProgramavimasTitle")
      out:line(t(result.failure == "busy" and "results.busyPractice" or "results.systemPractice"), "ProgramavimasMuted")
      return out
    end
    if status.input == "custom" and result.output then
      local output = result.output
      verdict_title(out, result.verdict, t("results.customOutput"))
      local chips = {}
      if output.timeMs then table.insert(chips, { text = t("results.time", { ms = output.timeMs }) }) end
      if output.memoryBytes then
        table.insert(chips, { text = t("results.memory", { mb = megabytes(output.memoryBytes) }) })
      end
      chip_line(out, chips)
      custom_section(out, output, context.custom, width)
    else
      verdict_title(out, result.verdict, t("judging.finished"))
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
      tests_section(out, tests, t("results.samplesTitle"), width)
    end
  else
    -- A graded submission.
    local submission = result.submission
    verdict_title(out, submission.verdict, t("judging." .. submission.state))
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
    tests_section(out, tests, t("results.testsTitle"), width)
  end
  if #(result.diagnostics or {}) > 0 then out:nl():line(t("results.compilerMessages"), "ProgramavimasMuted") end
  general_messages(out, result.general)
  if #tests > 0 then out:nl():line(t("help.hint"), "ProgramavimasFaint") end
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
    -- The cursor's line marks the test <CR> acts on, while the view has the cursor.
    vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter", "WinLeave" }, {
      buffer = buf,
      callback = function(event)
        vim.wo[0][0].cursorline = event.event ~= "WinLeave"
      end,
    })
    -- Data pairs sit side by side when the window is wide enough.
    ui.follow_width(buf, function() M.redraw() end)
  end
  return buf
end

function M.redraw()
  local buf = vim.fn.bufnr(BUFFER)
  if buf == -1 then return end
  local win = vim.fn.win_findbuf(buf)[1]
  local width = win and ui.text_width(win) or vim.o.columns
  local out = M.build(M.state, M.context, width)
  ui.render(buf, out.lines, out.marks)
  ui.drawn(buf, width)
end

--- Shows the view (keeping the cursor where it was).
function M.show()
  local buf = buffer()
  if ui.window_of(buf) then return M.redraw() end
  local current = vim.api.nvim_get_current_win()
  vim.cmd(("botright %dsplit"):format(config.options.results.height))
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.wo[win][0].number = false
  vim.wo[win][0].relativenumber = false
  vim.wo[win][0].signcolumn = "no"
  vim.wo[win][0].wrap = false
  vim.wo[win][0].list = false
  vim.wo[win][0].colorcolumn = ""
  vim.wo[win][0].winfixheight = true
  if vim.api.nvim_win_is_valid(current) then vim.api.nvim_set_current_win(current) end
  M.redraw()
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
---@param custom? programavimas.CustomInput  The input of a run with custom input
function M.set(state, fresh, attempts, custom)
  if fresh then M.context = { open = {}, started_at = os.time(), custom = custom } end
  if attempts then M.context.attempts = attempts end
  M.state = state
  M.show()
end

return M
