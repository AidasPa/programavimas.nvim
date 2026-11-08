local latex = require("programavimas.latex")

local function check(cases)
  for source, expected in pairs(cases) do
    eq(expected, latex.convert(source), source)
  end
end

describe("latex", function()
  it("writes relations and operators with KaTeX's spacing", function()
    check({
      ["1 \\le n \\le 10^5"] = "1 ≤ n ≤ 10⁵",
      ["-100 \\le a, b, c \\le 100"] = "−100 ≤ a, b, c ≤ 100",
      ["a\\ne b"] = "a ≠ b",
      ["a \\neq b"] = "a ≠ b",
      ["x \\geq 0"] = "x ≥ 0",
      ["2 \\cdot 10^9"] = "2 · 10⁹",
      ["3 \\times 4"] = "3 × 4",
      ["a \\bmod b"] = "a mod b",
      ["x \\in S"] = "x ∈ S",
      ["a \\not= b"] = "a ≠ b",
      ["\\pm 1"] = "± 1",
      ["n \\to \\infty"] = "n → ∞",
      ["x \\equiv 1 \\pmod{3}"] = "x ≡ 1 (mod 3)",
    })
  end)

  it("names Greek letters and symbols", function()
    check({
      ["\\alpha + \\beta"] = "α + β",
      ["\\alpha\\beta"] = "αβ",
      ["\\Delta x"] = "Δx",
      ["2\\pi r"] = "2πr",
      ["\\varepsilon"] = "ε",
      ["1, 2, \\ldots, n"] = "1, 2, …, n",
      ["a_1 + \\cdots + a_n"] = "a₁ + ⋯ + aₙ",
      ["\\emptyset"] = "∅",
      ["90^\\circ"] = "90°",
      ["f'(x)"] = "f′(x)",
    })
  end)

  it("raises and lowers when every character has a Unicode form", function()
    check({
      ["10^{18}"] = "10¹⁸",
      ["2^{31}-1"] = "2³¹−1",
      ["10^18"] = "10¹8",
      ["a_i"] = "aᵢ",
      ["a_{i+1}"] = "aᵢ₊₁",
      ["x_{max}"] = "xₘₐₓ",
      ["x^{-1}"] = "x⁻¹",
      ["n^{k}"] = "nᵏ",
      ["\\sum_{i=1}^n a_i"] = "∑ᵢ₌₁ⁿ aᵢ",
      ["x^{n + 1}"] = "xⁿ⁺¹",
    })
  end)

  it("keeps the caret or underscore when a character has no such form", function()
    check({
      ["a_{i,j}"] = "a_(i,j)",
      ["a_b"] = "a_b",
      ["2^{n/2}"] = "2^(n/2)",
      ["x^q"] = "x^q",
      ["2^{\\frac{n}{2}}"] = "2^(n/2)",
    })
  end)

  it("writes fractions on one line, bracketing compound parts", function()
    check({
      ["\\frac{a}{b}"] = "a/b",
      ["\\frac12"] = "1/2",
      ["\\frac{a + b + c}{2}"] = "(a + b + c)/2",
      ["p = \\frac{a + b + c}{2}"] = "p = (a + b + c)/2",
      ["\\dfrac{n(n+1)}{2}"] = "(n(n+1))/2",
      ["\\frac{1}{x^2}"] = "1/x²",
      ["\\frac{a}{b - c}"] = "a/(b − c)",
    })
  end)

  it("writes roots", function()
    check({
      ["\\sqrt{x}"] = "√x",
      ["\\sqrt{2}"] = "√2",
      ["\\sqrt{p(p-a)(p-b)(p-c)}"] = "√(p(p−a)(p−b)(p−c))",
      ["S = \\sqrt{p(p-a)(p-b)(p-c)}"] = "S = √(p(p−a)(p−b)(p−c))",
      ["\\sqrt[3]{x}"] = "∛x",
      ["\\sqrt[n]{x}"] = "ⁿ√x",
      ["\\sqrt{a^2 + b^2}"] = "√(a² + b²)",
    })
  end)

  it("shows text, delimiters, spacing and fonts", function()
    check({
      ["\\text{if } x > 0"] = "if x > 0",
      ["\\text{kai } n \\ge 1"] = "kai n ≥ 1",
      ["\\left( \\frac{a}{b} \\right)"] = "(a/b)",
      ["\\left\\{ x \\right\\}"] = "{x}",
      ["\\left. x \\right|"] = "x|",
      ["\\lfloor n/2 \\rfloor"] = "⌊n/2⌋",
      ["\\lceil \\log_2 n \\rceil"] = "⌈log₂ n⌉",
      ["\\max(a, b)"] = "max(a, b)",
      ["\\log n"] = "log n",
      ["\\operatorname{lcm}(a, b)"] = "lcm(a, b)",
      ["\\mathbb{R}"] = "ℝ",
      ["a\\,b\\;c\\quad d"] = "a b c  d",
      ["a\\!b"] = "ab",
      ["\\{1, 2\\}"] = "{1, 2}",
      ["50\\%"] = "50%",
      ["\\bar{x}"] = "x̄",
      ["\\overline{AB}"] = "A̅B̅",
      ["\\vec{v}"] = "v⃗",
      ["\\displaystyle\\sum x"] = "∑x",
      ["x % a comment\n+ 1"] = "x + 1",
    })
  end)

  it("breaks lines at \\\\ and in aligned environments", function()
    check({
      ["a = 1 \\\\ b = 2"] = "a = 1\nb = 2",
      ["\\begin{aligned} x &= 1 \\\\ y &= 2 \\end{aligned}"] = "x = 1\ny = 2",
    })
  end)

  it("answers nil for what it can't show faithfully", function()
    for _, source in ipairs({
      "\\binom{n}{k}",
      "\\begin{cases} 1 & x > 0 \\\\ 0 \\end{cases}",
      "\\begin{pmatrix} 1 & 2 \\end{pmatrix}",
      "\\mathcal{O}(n)",
      "\\frac{a}",
      "{a",
      "a}",
      "\\color{red}{x}",
      "\\hat{xy}",
      "x \\",
    }) do
      eq(nil, latex.convert(source), source)
    end
  end)
end)
