local results = require("programavimas.results")
local statement = require("programavimas.statement")
local ui = require("programavimas.ui")

local function text(lines) return table.concat(lines.lines, "\n") end

local function test(position, verdict, extra)
  return vim.tbl_extend("force", {
    position = position,
    sample = true,
    verdict = verdict,
    timeMs = 12,
    memoryBytes = 3 * 1048576,
    dataHidden = false,
  }, extra or {})
end

describe("results", function()
  it("shows a practice run's samples with the failing one open and its difference", function()
    local out = results.build({
      kind = "status",
      title = "Dvejetainė paieška",
      status = {
        kind = "practice",
        id = "r",
        input = "samples",
        language = "cpp",
        phase = "finished",
        result = {
          verdict = "wrong_answer",
          diagnostics = {},
          general = {},
          tests = {
            test(1, "accepted", { input = "1", expected = "1", actual = "1" }),
            test(2, "wrong_answer", { input = "3\n1 2 3", expected = "6\n", actual = "7\n" }),
          },
        },
      },
    }, { open = {} })
    local s = text(out)
    contains(s, "Dvejetainė paieška · Practice · not graded")
    contains(s, "✗ Wrong answer")
    contains(s, "1 of 2 samples · up to 12 ms · up to 3 MB")
    contains(s, "▸ ✓ Sample 1")
    contains(s, "▾ ✗ Sample 2")
    contains(s, "First difference on line 1: expected 6, got 7")
  end)

  it("shows a judged submission's tests, attempts and points", function()
    local out = results.build({
      kind = "status",
      title = "P",
      status = {
        kind = "judgement",
        id = "j",
        submissionId = "s",
        phase = "finished",
        progress = nil,
        result = {
          submission = { id = "s", state = "finished", verdict = "accepted", score = 10, maxScore = 10 },
          firstFailedTest = nil,
          diagnostics = {},
          general = {},
          tests = { test(1, "accepted", { sample = false, input = "1", expected = "1", actual = "1" }) },
        },
      },
    }, { open = {}, attempts = { left = 2, total = 5 } })
    local s = text(out)
    contains(s, "Graded · uses an attempt")
    contains(s, "✓ Accepted")
    contains(s, "1 of 1 tests · Points: 10 of 10 · Attempts left: 2 of 5")
    contains(s, "▸ ✓ Test 1")
  end)

  it("shows the judging step and progress while it runs", function()
    local s = text(results.build({
      kind = "status",
      title = "P",
      status = { kind = "practice", id = "r", input = "samples", language = "cpp", phase = "testing", progress = { done = 7, total = 12 } },
    }, { open = {} }))
    contains(s, "Testing  7/12")
    contains(s, "━")
  end)

  it("explains a refusal", function()
    local message = ui.refusal_message({ kind = "refused", status = 429, problem = { code = "no_attempts", resetsAt = "2026-11-07T22:00:00Z" } })
    eq("No attempts left today. Next attempt: 2026-11-08 00:00.", message)
    eq("Too many requests in a short time. Wait 30 s and try again.", ui.refusal_message({ kind = "refused", problem = { code = "rate_limited" }, retry_after = "30" }))
    eq("Your previous submission of this problem is still being judged. Submit again once it's checked.", ui.refusal_message({ kind = "refused", status = 429, problem = { code = "judging" } }))
    eq("Couldn't send. Your code is saved – try again.", ui.refusal_message({ kind = "refused", status = 400, problem = { code = "something_new" } }))
  end)
end)

describe("statement", function()
  local config = require("programavimas.config")
  local detail = {
    course = { id = "c", title = "Algoritmai" },
    topic = { id = "t", title = "Paieška", dueAt = nil },
    id = "p",
    title = "Dvejetainė paieška",
    status = { kind = "attempted", passed = 2, total = 5 },
    difficulty = 4,
    io = { kind = "files", input = "duom.txt", output = "rez.txt" },
    limits = { timeMs = 1000, memoryBytes = 268435456 },
    languages = { { code = "cpp", name = "C++" }, { code = "java", name = "Java" } },
    samples = {},
    statementMarkdown = "Raskite $x \\le 10^5$.\n",
    attempts = { left = 3, total = 5 },
    webUrl = "https://example.com",
  }

  it("draws the title, the course and topic, the facts and a rule above the statement", function()
    local out = statement.build(detail, 120)
    eq({
      "",
      "  Dvejetainė paieška",
      "  Algoritmai › Paieška",
      "",
      "  ◑ 2 of 5 tests pass · ▂▄▆ · Time limit 1 s · Memory 256 MB · duom.txt → rez.txt",
      "  C++, Java (browser only) · Attempts left: 3 of 5",
      ("─"):rep(120),
      "",
      "  Raskite x ≤ 10⁵.",
    }, out.lines)
  end)

  it("wraps the facts between them for a narrow window, never inside one", function()
    local lines = statement.build(detail, 52).lines
    eq("  ◑ 2 of 5 tests pass · ▂▄▆ · Time limit 1 s", lines[5])
    eq("  Memory 256 MB · duom.txt → rez.txt", lines[6])
    eq("  C++, Java (browser only) · Attempts left: 3 of 5", lines[7])
  end)

  it("keeps the server's Markdown for Markdown renderers when asked", function()
    config.setup({ language = "en", statement = { render = "markdown" } })
    local s = text(statement.build(detail))
    config.setup({ language = "en" })
    contains(s, "# Dvejetainė paieška")
    contains(s, "Algoritmai › Paieška")
    contains(s, "◑ 2 of 5 tests pass · ▂▄▆ · Time limit 1 s · Memory 256 MB · `duom.txt` → `rez.txt` · C++, Java (browser only) · Attempts left: 3 of 5")
    contains(s, "---\n\nRaskite $x \\le 10^5$.")
  end)

  it("refuses an unknown rendering", function()
    local ok = pcall(config.setup, { statement = { render = "html" } })
    config.setup({ language = "en" })
    eq(false, ok)
  end)
end)

describe("statement window", function()
  local markdown = table.concat({
    "Duotas masyvas ir užklausos, kurias reikia atsakyti greitai, nes jų daug.",
    "Žr. [aprašą](https://example.com/wiki/paieska).",
    "**Pavyzdys 1**",
    "**Pradiniai duomenys**",
    "```text\n1 2\n```",
    "**Rezultatai**",
    "```text\n3\n```",
    "**Pavyzdys 2**",
    "**Pradiniai duomenys**",
    "```text\n4 5\n```",
    "**Rezultatai**",
    "```text\n9\n```",
  }, "\n\n") .. "\n"
  local detail = {
    course = { id = "c2", title = "Kursas" },
    id = "p2",
    title = "Suma",
    status = { kind = "not_started" },
    io = { kind = "stdio" },
    limits = { timeMs = 1000, memoryBytes = 67108864 },
    languages = {},
    samples = {},
    statementMarkdown = markdown,
    webUrl = "https://example.com",
  }

  local function window()
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.b[vim.api.nvim_win_get_buf(win)].programavimas_statement then return win end
    end
  end
  local function line_of(win, text)
    for index, line in ipairs(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)) do
      if line:find(text, 1, true) then return index end
    end
  end
  local function resize(win, width)
    vim.api.nvim_win_set_width(win, width)
    vim.api.nvim_exec_autocmds("WinResized", {})
    vim.wait(200, function() return false end)
    return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
  end

  it("is drawn for its window, again when the width changes, keeping the reading place", function()
    vim.o.columns = 120
    statement.show(detail, true)
    local win = window()
    for _, line in ipairs(resize(win, 70)) do assert(vim.api.nvim_strwidth(line) <= 70, line) end
    vim.api.nvim_win_set_cursor(win, { line_of(win, "Pavyzdys 2"), 0 })
    local lines = resize(win, 36)
    for _, line in ipairs(lines) do assert(vim.api.nvim_strwidth(line) <= 36, line) end
    contains(table.concat(lines, "\n"), "  Duotas masyvas ir užklausos,")
    eq(line_of(win, "Pavyzdys 2"), vim.api.nvim_win_get_cursor(win)[1])
    eq(false, vim.wo[win].cursorline)
    eq("", vim.wo[win].colorcolumn)
  end)

  it("opens the link under the cursor with <CR>", function()
    local win = window()
    local opened
    local open = vim.ui.open
    vim.ui.open = function(url) opened = url end
    vim.api.nvim_set_current_win(win)
    local row = line_of(win, "aprašą")
    local col = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1]:find("aprašą", 1, true)
    vim.api.nvim_win_set_cursor(win, { row, col })
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
    vim.ui.open = open
    eq("https://example.com/wiki/paieska", opened)
    statement.forget()
  end)
end)
