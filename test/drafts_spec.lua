local drafts = require("programavimas.drafts")

local function record(serverAt, text) return { serverAt = serverAt, sha256 = vim.fn.sha256(text) } end
local function draft(code, serverAt) return { language = "python", code = code, savedAt = "2026-11-08T07:00:00Z", serverAt = serverAt } end

local function decide(input)
  return drafts.decide(vim.tbl_extend("keep", input, { pristine = false, modified = false }))
end

describe("draft sync", function()
  it("sends work the server has not seen when it holds no draft", function()
    eq("push", decide({ text = "print(1)\n" }))
    eq("push", decide({ text = "print(2)\n", record = record("s1", "print(1)\n") }))
  end)

  it("sends nothing when the file is blank, the starter code, or already sent", function()
    eq("none", decide({ text = "", pristine = true }))
    eq("none", decide({ text = "print(1)\n", record = record("s1", "print(1)\n") }))
  end)

  it("only records the match when both hold the same code", function()
    eq("record", decide({ text = "print(1)\n", draft = draft("print(1)\n", "s1") }))
    eq("record", decide({ text = "print(1)\n", draft = draft("print(1)\n", "s2"), record = record("s1", "x"), modified = true }))
  end)

  it("sends the file when only the file changed since the last match", function()
    eq("push", decide({ text = "print(2)\n", draft = draft("print(1)\n", "s1"), record = record("s1", "print(1)\n") }))
    -- Unsaved changes do not matter: the saved file is what goes.
    eq("push", decide({ text = "print(2)\n", draft = draft("print(1)\n", "s1"), record = record("s1", "print(1)\n"), modified = true }))
  end)

  it("takes the server's copy when only it changed", function()
    eq("take", decide({ text = "print(1)\n", draft = draft("print(9)\n", "s2"), record = record("s1", "print(1)\n") }))
  end)

  it("takes the server's copy into a blank or starter file", function()
    eq("take", decide({ text = "", draft = draft("print(9)\n", "s2"), pristine = true }))
    eq("take", decide({ text = "# write here\n", draft = draft("print(9)\n", "s2"), pristine = true }))
  end)

  it("asks when both changed, when nothing says which is newer, or over unsaved changes", function()
    eq("ask", decide({ text = "print(2)\n", draft = draft("print(9)\n", "s2"), record = record("s1", "print(1)\n") }))
    eq("ask", decide({ text = "print(2)\n", draft = draft("print(9)\n", "s2") }))
    eq("ask", decide({ text = "print(1)\n", draft = draft("print(9)\n", "s2"), record = record("s1", "print(1)\n"), modified = true }))
    eq("ask", decide({ text = "", draft = draft("print(9)\n", "s2"), pristine = true, modified = true }))
  end)
end)
