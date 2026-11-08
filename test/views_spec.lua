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
    eq("Couldn't send. Your code is saved – try again.", ui.refusal_message({ kind = "refused", status = 400, problem = { code = "something_new" } }))
  end)
end)

describe("statement", function()
  it("puts the problem's facts above the server's Markdown", function()
    local s = text(statement.build({
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
      statementMarkdown = "Raskite $x$.\n",
      attempts = { left = 3, total = 5 },
      webUrl = "https://example.com",
    }))
    contains(s, "# Dvejetainė paieška")
    contains(s, "Algoritmai · Paieška")
    contains(s, "◑ 2 of 5 tests pass · ▂▄▆ · Time limit 1 s · Memory 256 MB · `duom.txt` → `rez.txt` · C++, Java (browser only) · Attempts left: 3 of 5")
    contains(s, "Raskite $x$.")
  end)
end)
