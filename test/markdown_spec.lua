local markdown = require("programavimas.markdown")
local ui = require("programavimas.ui")

--- Draws Markdown at `width` columns: the lines, the builder (marks, links) and the anchors.
local function draw(text, width)
  local out = ui.lines()
  local anchors = markdown.render(out, text, { width = width or 60, labels = { image = "Image" } })
  return out.lines, out, anchors
end

--- The groups highlighting `part` of line `line` (1-based), first occurrence.
local function groups_at(out, line, part)
  local from = out.lines[line]:find(part, 1, true)
  assert(from, ("%q not on line %d: %q"):format(part, line, out.lines[line] or ""))
  local col, end_col = from - 1, from - 1 + #part
  local found = {}
  for _, mark in ipairs(out.marks) do
    if mark.line == line - 1 and mark.col <= col and mark.end_col >= end_col then table.insert(found, mark.hl) end
  end
  table.sort(found)
  return found
end

local function cells(line) return vim.api.nvim_strwidth(line) end

--- Whether marks of `group` cover all of line `line` (1-based).
local function covered(out, line, group)
  local seen = {}
  for _, mark in ipairs(out.marks) do
    if mark.line == line - 1 and mark.hl == group then
      for col = mark.col, mark.end_col - 1 do seen[col] = true end
    end
  end
  for col = 0, #out.lines[line] - 1 do
    if not seen[col] then return false end
  end
  return true
end

--- A line of a band `width` cells wide showing `text`.
local function band(text, width) return "  " .. text .. (" "):rep(width - 2 - cells(text)) end

describe("markdown", function()
  it("drops the markup of emphasis, code, links and escapes, and highlights them", function()
    local lines, out = draw(
      "Read **both *numbers*** and `n_max` — [the site](<https://example.com/a_(b)>), ~~old~~.\n\n"
        .. "a\\*b\\_c \\`d\\` \\[e\\](f) \\<script> \\$5 \\~\\~g\\~\\~ \\&amp;\n",
      100
    )
    eq({ "Read both numbers and n_max — the site, old.", "", "a*b_c `d` [e](f) <script> $5 ~~g~~ &amp;" }, lines)
    eq({ "ProgramavimasStrong" }, groups_at(out, 1, "both"))
    eq({ "ProgramavimasEmphasis", "ProgramavimasStrong" }, groups_at(out, 1, "numbers"))
    eq({ "ProgramavimasCode" }, groups_at(out, 1, "n_max"))
    eq({ "ProgramavimasLink" }, groups_at(out, 1, "the site"))
    eq({ "ProgramavimasStrike" }, groups_at(out, 1, "old"))
    eq({ { line = 0, col = 32, end_col = 40, url = "https://example.com/a_(b)" } }, out.links)
  end)

  it("wraps at spaces to the width, keeps hard breaks, and cuts only what can't fit a line", function()
    local lines = draw("Pirmoje eilutėje yra du skaičiai `a b` ir dar daugiau žodžių\\\nnauja eilutė https://example.com/labai/ilgas/adresas\n", 24)
    eq({
      "Pirmoje eilutėje yra du",
      "skaičiai a b ir dar",
      "daugiau žodžių",
      "nauja eilutė",
      "https://example.com/laba",
      "i/ilgas/adresas",
    }, lines)
    for _, line in ipairs(lines) do assert(cells(line) <= 24, line) end
  end)

  it("draws headings without their marks", function()
    local lines, out = draw("## Pradiniai duomenys\n\nTekstas.\n\n### Smulkiau\n")
    eq({ "Pradiniai duomenys", "", "Tekstas.", "", "Smulkiau" }, lines)
    eq({ "ProgramavimasHeading" }, groups_at(out, 1, "Pradiniai"))
    eq({ "ProgramavimasStrong" }, groups_at(out, 5, "Smulkiau"))
  end)

  it("hangs list items under their text, numbers aligned, nested lists with their item", function()
    local lines, out = draw(
      "- pirmas punktas, kurio tekstas netelpa vienoje eilutėje\n- antras\n\n"
        .. "9. devintas\n10. dešimtas\n\n    - vidinis\n    - kitas\n11. paskutinis\n",
      30
    )
    eq({
      "• pirmas punktas, kurio",
      "  tekstas netelpa vienoje",
      "  eilutėje",
      "• antras",
      "",
      " 9. devintas",
      "10. dešimtas",
      "    ◦ vidinis",
      "    ◦ kitas",
      "11. paskutinis",
    }, lines)
    eq({ "ProgramavimasListMarker" }, groups_at(out, 1, "•"))
  end)

  it("puts a formula of its own on an indented line and leaves an item with one apart", function()
    local lines, out = draw("1. Raskite:\n\n   $$\n   p = \\frac{a + b + c}{2}\n   $$\n2. Toliau $x_i \\ne 0$.\n")
    eq({ "1. Raskite:", "", "       p = (a + b + c)/2", "", "2. Toliau xᵢ ≠ 0." }, lines)
    eq({ "ProgramavimasMath" }, groups_at(out, 3, "p = (a + b + c)/2"))
    eq({ "ProgramavimasMath" }, groups_at(out, 5, "xᵢ ≠ 0"))
  end)

  it("shows a formula it can't convert as LaTeX", function()
    local lines, out = draw("Kai $\\binom{n}{k}$:\n\n$$\n\\begin{cases} 1 \\\\ 0 \\end{cases}\n$$\n")
    eq({ "Kai \\binom{n}{k}:", "", "    \\begin{cases} 1 \\\\ 0 \\end{cases}" }, lines)
    eq({ "ProgramavimasMath" }, groups_at(out, 1, "\\binom{n}{k}"))
  end)

  it("draws a code block as a band across the width, with its language", function()
    local lines, out = draw("```cpp\nint main() {\n\treturn 0;\n}\n```\n\n```text\nplain\n```\n", 30)
    eq({
      "                         C++  ",
      "  int main() {                ",
      "      return 0;               ",
      "  }                           ",
      "                              ",
      "",
      "                              ",
      "  plain                       ",
      "                              ",
    }, lines)
    for line = 1, 5 do eq(true, covered(out, line, "ProgramavimasCodeBlock"), lines[line]) end
    eq({ "ProgramavimasCodeBlock", "ProgramavimasMuted" }, groups_at(out, 1, "C++"))
  end)

  it("cuts a code line longer than its band, marking where it goes on", function()
    local lines, out = draw("```text\nabcdefghijklmnopqrstuvwxyz0123456789\n```\n", 20)
    eq({
      band("", 20),
      band("abcdefghijklmnop", 20),
      band("↪ qrstuvwxyz0123", 20),
      band("↪ 456789", 20),
      band("", 20),
    }, lines)
    eq({ "ProgramavimasCodeBlock", "ProgramavimasFaint" }, groups_at(out, 3, "↪"))
  end)

  it("draws notes, warnings and hints with a bar in their colour, and plain quotes", function()
    local lines, out = draw("> **Dėmesio**\n>\n> Atsargiai su `int`.\n\n> **Hint**\n>\n> Rūšiuok.\n\n> Citata\n")
    eq({ "▎ Dėmesio", "▎ Atsargiai su int.", "", "▎ Hint", "▎ Rūšiuok.", "", "▎ Citata" }, lines)
    eq({ "ProgramavimasWarning" }, groups_at(out, 2, "▎"))
    eq({ "ProgramavimasStrong", "ProgramavimasWarning" }, groups_at(out, 1, "Dėmesio"))
    eq({ "ProgramavimasHint" }, groups_at(out, 5, "▎"))
    eq({ "ProgramavimasQuote" }, groups_at(out, 7, "▎"))
  end)

  it("draws rules across the width and images as a line that opens", function()
    local lines, out = draw("---\n\n![Grafas](https://assets.example/blobs/abc)\n\n![](https://assets.example/blobs/def)\n", 20)
    eq({ ("─"):rep(20), "", "▣ Grafas", "", "▣ Image" }, lines)
    eq("https://assets.example/blobs/abc", out.links[1].url)
    eq(0, out.links[1].col)
  end)

  it("lays out the samples side by side when they fit, else one under the other", function()
    local text = table.concat({
      "**Pavyzdys 1**",
      "`duom.txt`",
      "```text\n5 3\n1 2 4\n```",
      "`rez.txt`",
      "```text\n2\n```",
      "**Pavyzdys 2**",
      "**Pradiniai duomenys**",
      "*Tuščia*",
      "**Rezultatai**",
      "```text\n0\n```",
    }, "\n\n") .. "\n"
    -- Both panes as wide as the wider needs, at least 24 cells, 3 apart.
    local wide, out = draw(text, 60)
    local function row(left, right) return band(left, 24) .. "   " .. band(right, 24) end
    eq({
      "Pavyzdys 1",
      "duom.txt" .. (" "):rep(19) .. "rez.txt",
      row("", ""),
      row("5 3", "2"),
      row("1 2 4", ""),
      row("", ""),
      "",
      "Pavyzdys 2",
      "Pradiniai duomenys" .. (" "):rep(9) .. "Rezultatai",
      row("", ""),
      row("Tuščia", "0"),
      row("", ""),
    }, wide)
    eq({ "ProgramavimasStrong" }, groups_at(out, 1, "Pavyzdys 1"))
    eq({ "ProgramavimasMuted" }, groups_at(out, 2, "duom.txt"))
    eq({ "ProgramavimasCodeBlock", "ProgramavimasEmphasis", "ProgramavimasMuted" }, groups_at(out, 11, "Tuščia"))
    local narrow = draw(text, 30)
    eq({
      "Pavyzdys 1",
      "duom.txt",
      band("", 30),
      band("5 3", 30),
      band("1 2 4", 30),
      band("", 30),
      "",
      "rez.txt",
      band("", 30),
      band("2", 30),
      band("", 30),
    }, vim.list_slice(narrow, 1, 11))
  end)

  it("aligns a pipe table, rules its header and wraps cells that don't fit", function()
    local text = table.concat({
      "| Užklausa $x$ | Atsakymas | Kodėl |",
      "| :--- | ---: | :---: |",
      "| 2 | 2 | du |",
      "| 10 | 5 | visi elementai<br>ne didesni |",
      "| `a\\|b` | 1 | x | ignoruojama |",
    }, "\n") .. "\n"
    local lines, out = draw(text, 80)
    eq({
      "Užklausa x │ Atsakymas │     Kodėl",
      "───────────┼───────────┼───────────────",
      "2          │         2 │       du",
      "───────────┼───────────┼───────────────",
      "10         │         5 │ visi elementai",
      "           │           │   ne didesni",
      "───────────┼───────────┼───────────────",
      "a|b        │         1 │       x",
    }, lines)
    eq({ "ProgramavimasStrong" }, groups_at(out, 1, "Atsakymas"))
    eq({ "ProgramavimasMath", "ProgramavimasStrong" }, groups_at(out, 1, "x"))
    local narrow = draw("| Pirmas stulpelis | Antras ilgas stulpelis |\n| --- | --- |\n| a | b |\n", 30)
    for _, line in ipairs(narrow) do assert(cells(line) <= 30, line) end
    eq("Pirmas        │ Antras ilgas", narrow[1])
    eq("stulpelis     │ stulpelis", narrow[2])
  end)

  it("anchors every line to its block, for keeping the place when the width changes", function()
    local _, _, anchors = draw("Pirmas.\n\nAntras ilgas sakinys.\n", 10)
    eq({ 1, 1, 2, 2, 2 }, { anchors[1], anchors[2], anchors[3], anchors[4], anchors[5] })
  end)
end)
