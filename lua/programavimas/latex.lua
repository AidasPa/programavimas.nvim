-- Formulas as plain Unicode for the statement: the notation of programming problems
-- (relations and operators, Greek letters, fractions, roots, sub- and superscripts, \text,
-- \left…\right, spacing, dots, aligned lines) the way KaTeX shows it on the web, as far as
-- characters can. `convert` answers nil for anything it can't show faithfully (an unknown
-- command, a matrix, cases, an unbalanced brace), and the statement shows the LaTeX itself.
-- Pure.

local M = {}

-- Ordinary symbols: written as they are, without spaces of their own.
local SYMBOLS = {
  alpha = "α", beta = "β", gamma = "γ", delta = "δ", epsilon = "ϵ", varepsilon = "ε",
  zeta = "ζ", eta = "η", theta = "θ", vartheta = "ϑ", iota = "ι", kappa = "κ", lambda = "λ",
  mu = "μ", nu = "ν", xi = "ξ", omicron = "ο", pi = "π", varpi = "ϖ", rho = "ρ", varrho = "ϱ",
  sigma = "σ", varsigma = "ς", tau = "τ", upsilon = "υ", phi = "ϕ", varphi = "φ", chi = "χ",
  psi = "ψ", omega = "ω",
  Gamma = "Γ", Delta = "Δ", Theta = "Θ", Lambda = "Λ", Xi = "Ξ", Pi = "Π", Sigma = "Σ",
  Upsilon = "Υ", Phi = "Φ", Psi = "Ψ", Omega = "Ω",
  infty = "∞", partial = "∂", nabla = "∇", forall = "∀", exists = "∃", nexists = "∄",
  emptyset = "∅", varnothing = "∅", neg = "¬", lnot = "¬", angle = "∠", triangle = "△",
  ldots = "…", dots = "…", dotsc = "…", dotsb = "⋯", cdots = "⋯", vdots = "⋮", ddots = "⋱",
  prime = "′", degree = "°", hbar = "ℏ", ell = "ℓ", aleph = "ℵ", Re = "ℜ", Im = "ℑ",
  sum = "∑", prod = "∏", coprod = "∐", int = "∫", iint = "∬", oint = "∮",
  bigcup = "⋃", bigcap = "⋂",
  lfloor = "⌊", rfloor = "⌋", lceil = "⌈", rceil = "⌉", langle = "⟨", rangle = "⟩",
  vert = "|", Vert = "‖", lvert = "|", rvert = "|", lVert = "‖", rVert = "‖",
  backslash = "\\", surd = "√", top = "⊤", bot = "⊥", clubsuit = "♣", diamondsuit = "♢",
  heartsuit = "♡", spadesuit = "♠", checkmark = "✓", dagger = "†", S = "§", P = "¶",
}

-- Relations and binary operators: KaTeX sets them apart, so they get a space on each side.
local SPACED = {
  le = "≤", leq = "≤", leqslant = "≤", ge = "≥", geq = "≥", geqslant = "≥", ne = "≠",
  neq = "≠", lt = "<", gt = ">", approx = "≈", equiv = "≡", sim = "∼", simeq = "≃",
  cong = "≅", propto = "∝", ll = "≪", gg = "≫", prec = "≺", succ = "≻", preceq = "⪯",
  succeq = "⪰", cdot = "·", times = "×", div = "÷", pm = "±", mp = "∓", ast = "∗",
  star = "⋆", circ = "∘", bullet = "•", oplus = "⊕", ominus = "⊖", otimes = "⊗", odot = "⊙",
  ["in"] = "∈", notin = "∉", ni = "∋", subset = "⊂", subseteq = "⊆", subsetneq = "⊊",
  supset = "⊃", supseteq = "⊇", cup = "∪", cap = "∩", setminus = "∖", land = "∧",
  lor = "∨", wedge = "∧", vee = "∨", to = "→", rightarrow = "→", leftarrow = "←",
  gets = "←", leftrightarrow = "↔", Rightarrow = "⇒", Leftarrow = "⇐",
  Leftrightarrow = "⇔", implies = "⟹", impliedby = "⟸", iff = "⟺", mapsto = "↦",
  longrightarrow = "⟶", longleftarrow = "⟵", uparrow = "↑", downarrow = "↓", mid = "∣",
  nmid = "∤", parallel = "∥", perp = "⊥", vdash = "⊢", models = "⊨", colon = ":",
  bmod = "mod", mod = "mod",
}

-- Operator names: upright words, a space before an operand that follows.
local FUNCTIONS = {
  log = true, ln = true, lg = true, exp = true, sin = true, cos = true, tan = true,
  cot = true, sec = true, csc = true, arcsin = true, arccos = true, arctan = true,
  sinh = true, cosh = true, tanh = true, max = true, min = true, sup = true, inf = true,
  lim = true, limsup = true, liminf = true, det = true, deg = true, dim = true, ker = true,
  gcd = true, arg = true, Pr = true, hom = true,
}

local BLACKBOARD = {
  N = "ℕ", Z = "ℤ", Q = "ℚ", R = "ℝ", C = "ℂ", P = "ℙ", H = "ℍ", E = "𝔼",
}

-- Combining marks over a letter: \bar{x} x̄, \vec{v} v⃗.
local ACCENTS = {
  bar = "\204\132", overline = "\204\133", hat = "\204\130", widehat = "\204\130",
  tilde = "\204\131", widetilde = "\204\131", vec = "\226\131\151", dot = "\204\135",
  ddot = "\204\136", underline = "\204\178",
}

-- Text inside \text{…} and font commands: its argument as written.
local TEXT = {
  text = true, textrm = true, textit = true, textbf = true, textsf = true, texttt = true,
  textnormal = true, mbox = true, mathrm = true, mathit = true, mathbf = true, mathsf = true,
  mathtt = true, mathnormal = true, boldsymbol = true, bm = true, operatorname = true,
  mathop = true, mathord = true, mathrel = true, mathbin = true,
}

-- Size and style switches with nothing to show.
local IGNORED = {
  displaystyle = true, textstyle = true, scriptstyle = true, scriptscriptstyle = true,
  limits = true, nolimits = true, nonumber = true, notag = true, middle = true,
  big = true, Big = true, bigg = true, Bigg = true, bigl = true, bigr = true, Bigl = true,
  Bigr = true, biggl = true, biggr = true, Biggl = true, Biggr = true, bigm = true,
  Bigm = true, left = true, right = true,
}

-- Environments that are only lines: `\\` breaks them and `&` aligns (dropped here).
local LINE_ENVIRONMENTS = {
  aligned = true, align = true, ["align*"] = true, gathered = true, gather = true,
  ["gather*"] = true, split = true, alignat = false, multline = true, ["multline*"] = true,
}

local SUPERSCRIPT = {
  ["0"] = "⁰", ["1"] = "¹", ["2"] = "²", ["3"] = "³", ["4"] = "⁴", ["5"] = "⁵", ["6"] = "⁶",
  ["7"] = "⁷", ["8"] = "⁸", ["9"] = "⁹", ["+"] = "⁺", ["-"] = "⁻", ["−"] = "⁻", ["="] = "⁼",
  ["("] = "⁽", [")"] = "⁾", a = "ᵃ", b = "ᵇ", c = "ᶜ", d = "ᵈ", e = "ᵉ", f = "ᶠ", g = "ᵍ",
  h = "ʰ", i = "ⁱ", j = "ʲ", k = "ᵏ", l = "ˡ", m = "ᵐ", n = "ⁿ", o = "ᵒ", p = "ᵖ", r = "ʳ",
  s = "ˢ", t = "ᵗ", u = "ᵘ", v = "ᵛ", w = "ʷ", x = "ˣ", y = "ʸ", z = "ᶻ", A = "ᴬ", B = "ᴮ",
  D = "ᴰ", E = "ᴱ", G = "ᴳ", H = "ᴴ", I = "ᴵ", J = "ᴶ", K = "ᴷ", L = "ᴸ", M = "ᴹ", N = "ᴺ",
  O = "ᴼ", P = "ᴾ", R = "ᴿ", T = "ᵀ", U = "ᵁ", V = "ⱽ", W = "ᵂ", ["α"] = "ᵅ", ["β"] = "ᵝ",
  ["γ"] = "ᵞ", ["δ"] = "ᵟ", ["ε"] = "ᵋ", ["θ"] = "ᶿ", ["ι"] = "ᶥ", ["ϕ"] = "ᵠ", ["φ"] = "ᵠ",
  ["χ"] = "ᵡ", ["′"] = "′", ["∘"] = "°", ["°"] = "°", ["∗"] = "*", ["*"] = "*",
}

local SUBSCRIPT = {
  ["0"] = "₀", ["1"] = "₁", ["2"] = "₂", ["3"] = "₃", ["4"] = "₄", ["5"] = "₅", ["6"] = "₆",
  ["7"] = "₇", ["8"] = "₈", ["9"] = "₉", ["+"] = "₊", ["-"] = "₋", ["−"] = "₋", ["="] = "₌",
  ["("] = "₍", [")"] = "₎", a = "ₐ", e = "ₑ", h = "ₕ", i = "ᵢ", j = "ⱼ", k = "ₖ", l = "ₗ",
  m = "ₘ", n = "ₙ", o = "ₒ", p = "ₚ", r = "ᵣ", s = "ₛ", t = "ₜ", u = "ᵤ", v = "ᵥ", x = "ₓ",
  ["β"] = "ᵦ", ["γ"] = "ᵧ", ["ρ"] = "ᵨ", ["ϕ"] = "ᵩ", ["φ"] = "ᵩ", ["χ"] = "ᵪ",
}

local DELIMITERS = {
  ["("] = "(", [")"] = ")", ["["] = "[", ["]"] = "]", ["|"] = "|", ["/"] = "/", ["."] = "",
  ["<"] = "⟨", [">"] = "⟩",
}

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"

local OPENING = { "(", "[", "{", "⌊", "⌈", "⟨" }
local CLOSING = { ")", "]", "}", "⌋", "⌉", "⟩", ",", ";" }

-- Stands for a space that must stay (\quad) while ordinary spaces are collapsed, and for
-- "no space here" before and after a \left…\right delimiter.
local HARD_SPACE = "\1"
local GLUE_BEFORE, GLUE_AFTER = "\2", "\3"

---@param text string
---@return string[]
local function chars(text)
  local list = {}
  for char in text:gmatch(CHAR) do table.insert(list, char) end
  return list
end

---@class programavimas.LatexToken
---@field kind "command"|"symbol"|"char"|"space"
---@field value string?

---@param source string
---@return programavimas.LatexToken[]?
local function tokenize(source)
  local tokens, i = {}, 1
  while i <= #source do
    local c = source:sub(i, i)
    if c == "\\" then
      local word = source:match("^%a+", i + 1)
      if word then
        table.insert(tokens, { kind = "command", value = word })
        i = i + 1 + #word
      else
        local symbol = source:match("^" .. CHAR, i + 1)
        if not symbol then return nil end
        table.insert(tokens, { kind = "symbol", value = symbol })
        i = i + 1 + #symbol
      end
    elseif c:match("%s") then
      table.insert(tokens, { kind = "space" })
      i = i + #source:match("^%s+", i)
    elseif c == "%" then
      -- A comment runs to the end of the line.
      i = (source:find("\n", i, true) or #source) + 1
    else
      local char = source:match("^" .. CHAR, i)
      table.insert(tokens, { kind = "char", value = char })
      i = i + #char
    end
  end
  return tokens
end

---@class programavimas.LatexParser
---@field tokens programavimas.LatexToken[]
---@field i integer
local Parser = {}
Parser.__index = Parser

function Parser:peek() return self.tokens[self.i] end

function Parser:next()
  local token = self.tokens[self.i]
  self.i = self.i + 1
  return token
end

function Parser:skip_spaces()
  while self:peek() and self:peek().kind == "space" do self.i = self.i + 1 end
end

--- Text up to `closer` (or the end when nil), converted; nil when it can't be.
---@param closer string?
---@return string?
function Parser:list(closer)
  local out = {}
  while true do
    local token = self:peek()
    if not token then
      if closer then return nil end
      return table.concat(out)
    end
    if token.kind == "char" and (token.value == "}" or token.value == closer) then
      if token.value ~= closer then return nil end
      self.i = self.i + 1
      return table.concat(out)
    end
    local piece = self:atom()
    if piece == nil then return nil end
    table.insert(out, piece)
  end
end

--- A command's argument: a group, a command or one character.
---@return string?
function Parser:argument()
  self:skip_spaces()
  local token = self:peek()
  if not token then return nil end
  if token.kind == "char" and token.value == "{" then
    self.i = self.i + 1
    return self:list("}")
  end
  if token.kind == "char" and token.value == "}" then return nil end
  return self:atom()
end

--- An argument as written in text mode (\text{…}): its characters and single spaces.
---@return string?
function Parser:text_argument()
  self:skip_spaces()
  local token = self:next()
  if not token then return nil end
  if token.kind == "char" and token.value ~= "{" then return token.value end
  if token.kind ~= "char" then return nil end
  local out, depth = {}, 1
  while true do
    token = self:next()
    if not token then return nil end
    if token.kind == "space" then
      table.insert(out, " ")
    elseif token.kind == "char" and token.value == "{" then
      depth = depth + 1
    elseif token.kind == "char" and token.value == "}" then
      depth = depth - 1
      if depth == 0 then return table.concat(out) end
    elseif token.kind == "char" then
      table.insert(out, token.value)
    elseif token.kind == "symbol" then
      if token.value == "\\" then return nil end
      table.insert(out, token.value == " " and " " or token.value)
    else
      -- A formula inside the text ($…$) or a command: let the caller show the LaTeX.
      local piece = SYMBOLS[token.value] or SPACED[token.value]
      if not piece then return nil end
      table.insert(out, piece)
    end
  end
end

--- An environment's name after \begin or \end.
---@return string?
function Parser:name()
  self:skip_spaces()
  local token = self:next()
  if not token or token.kind ~= "char" or token.value ~= "{" then return nil end
  local out = {}
  while true do
    token = self:next()
    if not token then return nil end
    if token.kind == "char" and token.value == "}" then return table.concat(out) end
    if token.kind ~= "char" then return nil end
    table.insert(out, token.value)
  end
end

--- A delimiter after \left, \right or \big: ( [ | . \{ \langle …
---@return string?
function Parser:delimiter()
  self:skip_spaces()
  local token = self:next()
  if not token then return nil end
  if token.kind == "char" then return DELIMITERS[token.value] end
  if token.kind == "symbol" then
    return ({ ["{"] = "{", ["}"] = "}", ["|"] = "‖" })[token.value]
  end
  if token.kind == "command" then return SYMBOLS[token.value] end
  return nil
end

--- Whether a converted operand reads as one unit (no brackets needed): `n`, `12`, `x²`, `(…)`.
---@param text string
local function simple(text)
  if text == "" then return true end
  if text:match("^%b()$") then return true end
  if text:find("[%s%+%-=<>/,:;]") then return false end
  for _, operator in ipairs({ "−", "·", "×", "÷", "±", "∓", "≤", "≥", "≠", "≈", "→", "∈" }) do
    if text:find(operator, 1, true) then return false end
  end
  return true
end

---@param text string
local function bracket(text) return simple(text) and text or "(" .. text .. ")" end

--- Super- or subscript characters when every character has one, else ^x, ^(…).
---@param text string
---@param map table<string, string>
---@param mark "^"|"_"
local function script(text, map, mark)
  local compact = text:gsub("[%s" .. HARD_SPACE .. "]", "")
  if compact == "" then return "" end
  local out = {}
  for _, char in ipairs(chars(compact)) do
    local mapped = map[char]
    if not mapped then
      local list = chars(compact)
      return mark .. (#list == 1 and compact or "(" .. compact .. ")")
    end
    table.insert(out, mapped)
  end
  return table.concat(out)
end

--- One unit: a character, a group, a script or a command with its arguments.
---@return string?
function Parser:atom()
  local token = self:next()
  if token.kind == "space" then return " " end
  if token.kind == "char" then
    local value = token.value
    if value == "{" then return self:list("}") end
    if value == "^" or value == "_" then
      local argument = self:argument()
      if argument == nil then return nil end
      return script(argument, value == "^" and SUPERSCRIPT or SUBSCRIPT, value)
    end
    if value == "-" then return "−" end
    if value == "'" then return "′" end
    if value == "~" then return " " end
    if value == "&" then return " " end
    if value == "$" or value == "#" then return nil end
    return value
  end
  if token.kind == "symbol" then
    local value = token.value
    if value == "\\" then return "\n" end
    if value == "," or value == ":" or value == ";" or value == ">" or value == " " then return " " end
    if value == "!" then return "" end
    if value == "|" then return "‖" end
    if ("{}%$#&_"):find(value, 1, true) then return value end
    return nil
  end
  return self:command(token.value)
end

--- A command and whatever arguments it takes.
---@param name string
---@return string?
function Parser:command(name)
  local function plain_space()
    -- The space that ends a command word is not a space of the formula.
    if self:peek() and self:peek().kind == "space" then self.i = self.i + 1 end
  end
  if SYMBOLS[name] then
    -- An ordinary symbol sits against a letter after it (\pi r: πr), not an operator.
    local after = self.tokens[self.i + 1]
    if self:peek() and self:peek().kind == "space" and after
      and (after.kind == "command" or (after.kind == "char" and after.value:match("^[%w\128-\255]")))
    then
      self.i = self.i + 1
    end
    return SYMBOLS[name]
  end
  if SPACED[name] then
    plain_space()
    return " " .. SPACED[name] .. " "
  end
  if FUNCTIONS[name] then
    plain_space()
    local after = self:peek()
    local operand = after and (after.kind == "command" or (after.kind == "char" and after.value:match("^[%w\128-\255]")))
    return name .. (operand and " " or "")
  end
  if IGNORED[name] then
    if name == "left" or name == "right" or name == "middle" or name:match("^[bB]ig") then
      local delimiter = self:delimiter()
      if not delimiter then return nil end
      -- Against what they enclose: no space inside \left( … \right).
      if name == "left" then return delimiter .. GLUE_AFTER end
      if name == "right" then return GLUE_BEFORE .. delimiter end
      return delimiter
    end
    plain_space()
    return ""
  end
  if name == "frac" or name == "dfrac" or name == "tfrac" or name == "cfrac" then
    local top = self:argument()
    local bottom = top and self:argument()
    if not bottom then return nil end
    return bracket(vim.trim(top)) .. "/" .. bracket(vim.trim(bottom))
  end
  if name == "sqrt" then
    self:skip_spaces()
    local index
    local token = self:peek()
    if token and token.kind == "char" and token.value == "[" then
      self.i = self.i + 1
      index = self:list("]")
      if not index then return nil end
    end
    local radicand = self:argument()
    if not radicand then return nil end
    radicand = vim.trim(radicand)
    local root = "√"
    if index then
      index = vim.trim(index)
      if index == "3" then
        root = "∛"
      elseif index == "4" then
        root = "∜"
      else
        local raised = script(index, SUPERSCRIPT, "^")
        if raised:sub(1, 1) == "^" then return nil end
        root = raised .. "√"
      end
    end
    return root .. (simple(radicand) and radicand or "(" .. radicand .. ")")
  end
  if TEXT[name] then
    local text = self:text_argument()
    if text == nil then return nil end
    return text
  end
  if name == "mathbb" then
    local argument = self:argument()
    return argument and BLACKBOARD[vim.trim(argument)]
  end
  if ACCENTS[name] then
    local argument = self:argument()
    if not argument then return nil end
    local list = chars(vim.trim(argument))
    if #list == 0 then return nil end
    local mark = ACCENTS[name]
    if #list > 1 then
      -- One mark per letter draws a line over a word; other accents belong to one letter.
      if name ~= "overline" and name ~= "bar" and name ~= "underline" then return nil end
      if name == "bar" then mark = ACCENTS.overline end
    end
    local out = {}
    for _, char in ipairs(list) do table.insert(out, char .. mark) end
    return table.concat(out)
  end
  if name == "pmod" then
    local argument = self:argument()
    return argument and " (mod " .. vim.trim(argument) .. ")"
  end
  if name == "not" then
    self:skip_spaces()
    local token = self:next()
    if not token then return nil end
    if token.kind == "char" and token.value == "=" then return " ≠ " end
    if token.kind == "command" and token.value == "in" then return " ∉ " end
    return nil
  end
  if name == "quad" or name == "qquad" then
    plain_space()
    return HARD_SPACE:rep(name == "quad" and 2 or 4)
  end
  if name == "begin" or name == "end" then
    local environment = self:name()
    if not environment or not LINE_ENVIRONMENTS[environment] then return nil end
    return name == "begin" and "" or "\n"
  end
  return nil
end

--- A formula as Unicode text (lines separated by "\n"), or nil when it can't be shown
--- faithfully.
---@param latex string
---@return string?
function M.convert(latex)
  local tokens = tokenize(latex)
  if not tokens then return nil end
  local parser = setmetatable({ tokens = tokens, i = 1 }, Parser)
  local ok, text = pcall(parser.list, parser, nil)
  if not ok or text == nil then return nil end
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    line = line:gsub("%s*" .. GLUE_BEFORE, ""):gsub(GLUE_AFTER .. "%s*", "")
    line = vim.trim(line:gsub("%s+", " ")):gsub(HARD_SPACE, " ")
    -- No space inside brackets or before punctuation, as KaTeX sets them.
    for _, open in ipairs(OPENING) do line = line:gsub(vim.pesc(open) .. " ", open) end
    for _, close in ipairs(CLOSING) do line = line:gsub(" " .. vim.pesc(close), close) end
    if line ~= "" then table.insert(lines, line) end
  end
  return table.concat(lines, "\n")
end

return M
