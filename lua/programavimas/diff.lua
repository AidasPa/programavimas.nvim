-- Line comparison for the results: which lines of the expected and the program's output
-- differ, and the first difference for the caption. A visual hint only; the judge's checker
-- decides the verdict. Trailing spaces are ignored, as the line checker ignores them. The
-- same rules as the VS Code extension's (apps/vscode/src/views/diff.ts). Pure.

local M = {}

--- Lines of an output: CRLF normalised, one final newline is not an extra empty line.
---@param text string
---@return string[]
function M.output_lines(text)
  local normalised = text:gsub("\r\n?", "\n")
  if normalised == "" then return {} end
  if normalised:sub(-1) == "\n" then normalised = normalised:sub(1, -2) end
  return vim.split(normalised, "\n", { plain = true })
end

---@param value string?
local function trim_end(value) return value and (value:gsub("%s+$", "")) or nil end

---@class programavimas.FirstDifference
---@field line integer
---@field expected string?  nil when the expected output has no such line
---@field actual string?

--- Per line of each side: true where it differs; and the first difference.
---@param expected string
---@param actual string
---@return { expected: boolean[], actual: boolean[], first: programavimas.FirstDifference? }
function M.compare(expected, actual)
  local want, got = M.output_lines(expected), M.output_lines(actual)
  local function differs(index)
    local a, b = want[index], got[index]
    return a == nil or b == nil or trim_end(a) ~= trim_end(b)
  end
  local first
  for index = 1, math.max(#want, #got) do
    if differs(index) then
      first = { line = index, expected = want[index], actual = got[index] }
      break
    end
  end
  local marks = { expected = {}, actual = {}, first = first }
  for index = 1, #want do marks.expected[index] = differs(index) end
  for index = 1, #got do marks.actual[index] = differs(index) end
  return marks
end

--- A value short enough for a one-line caption.
---@param value string
---@param max? integer  Characters
function M.clip(value, max)
  max = max or 40
  if vim.fn.strchars(value) <= max then return value end
  return vim.fn.strcharpart(value, 0, max - 1) .. "…"
end

return M
