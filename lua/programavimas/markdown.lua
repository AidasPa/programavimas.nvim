-- The statement's Markdown drawn as text: the API's `statementMarkdown` (written by
-- packages/content/src/markdown.ts, the source of truth for what it contains) parsed with the
-- Tree-sitter parsers Neovim bundles since 0.10 (`markdown`, `markdown_inline`) and laid out
-- at a width into a lines builder (ui.lua) with highlights and no markup characters left:
-- headings, paragraphs, emphasis, code, links, images, lists, code blocks, quotes (notes,
-- warnings and hints), rules, pipe tables, the samples, and formulas through latex.lua.
-- Pure apart from the parsers.

local latex = require("programavimas.latex")
local ui = require("programavimas.ui")

local M = {}

local CHAR = "[%z\1-\127\194-\244][\128-\191]*"
local BULLETS = { "•", "◦", "▪" }
local BAR = "▎"
local IMAGE = "▣"
local RULE = "─"
-- Columns between a band's edge and its text.
local PAD = 2
local PLAIN = { [""] = true, text = true, txt = true, plain = true, plaintext = true }
local LANGUAGE_NAMES = {
  c = "C", cpp = "C++", ["c++"] = "C++", cs = "C#", csharp = "C#", python = "Python",
  py = "Python", java = "Java", js = "JavaScript", javascript = "JavaScript", ts = "TypeScript",
  typescript = "TypeScript", pascal = "Pascal", go = "Go", rust = "Rust", lua = "Lua",
  sql = "SQL", bash = "Bash", sh = "Shell", json = "JSON", html = "HTML", css = "CSS",
}
-- The labels the server gives notes, warnings and hints (statement.json, lt and en).
local TONES = {
  Pastaba = "ProgramavimasNote",
  Note = "ProgramavimasNote",
  ["Dėmesio"] = "ProgramavimasWarning",
  Warning = "ProgramavimasWarning",
  ["Užuomina"] = "ProgramavimasHint",
  Hint = "ProgramavimasHint",
}
-- Words of the reader's language, set by `parse`.
local labels = { image = "Image" }
local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'", nbsp = " ", ndash = "–", mdash = "—" }

---@param text string
local function width_of(text) return vim.api.nvim_strwidth(text) end

---@param text string
local function expand_tabs(text) return (text:gsub("\t", "    ")) end

-- ------------------------------------------------------------------ parsing

---@class programavimas.Span  A run of inline text and its look
---@field text string
---@field hl string[]
---@field url string?
---@field atomic boolean?   Code and formulas: kept on one line when they fit
---@field brk boolean?      A line break
---@field math boolean?
---@field display boolean?  $$…$$
---@field latex string?     The formula as written, shown when it can't be converted
---@field image boolean?

---@param style { hl: string[], url: string? }
---@param group string?
---@param url string?
local function with(style, group, url)
  local hl = vim.list_extend({}, style.hl)
  if group and not vim.tbl_contains(hl, group) then table.insert(hl, group) end
  return { hl = hl, url = url or style.url }
end

---@param spans programavimas.Span[]
---@param text string
---@param style { hl: string[], url: string? }
local function emit(spans, text, style)
  if text == "" then return end
  table.insert(spans, { text = (text:gsub("\n", " ")), hl = style.hl, url = style.url })
end

--- The text between a node's first and last named children (its delimiters).
local function inner(node, source)
  local first, last
  for child in node:iter_children() do
    if child:named() then
      first = first or child
      last = child
    end
  end
  if not first or first == last then return vim.treesitter.get_node_text(node, source) end
  local _, _, from = first:end_()
  local _, _, to = last:start()
  return source:sub(from + 1, to)
end

local walk

---@param node TSNode
---@param source string
---@param style { hl: string[], url: string? }
---@param spans programavimas.Span[]
---@param cell boolean  Inside a table cell, where `\|` in code is a pipe
local function inline_node(node, source, style, spans, cell)
  local kind = node:type()
  local text = vim.treesitter.get_node_text(node, source)
  if kind:match("_delimiter$") then
    return
  elseif kind == "emphasis" then
    walk(node, source, with(style, "ProgramavimasEmphasis"), spans, cell)
  elseif kind == "strong_emphasis" then
    walk(node, source, with(style, "ProgramavimasStrong"), spans, cell)
  elseif kind == "strikethrough" then
    walk(node, source, with(style, "ProgramavimasStrike"), spans, cell)
  elseif kind == "code_span" then
    local code = inner(node, source):gsub("\n", " ")
    if code:match("^ .* $") and code:match("%S") then code = code:sub(2, -2) end
    if cell then code = code:gsub("\\|", "|") end
    table.insert(spans, { text = code, hl = with(style, "ProgramavimasCode").hl, url = style.url, atomic = true })
  elseif kind == "latex_block" then
    local source_tex = inner(node, source)
    local converted = latex.convert(source_tex)
    table.insert(spans, {
      text = converted or vim.trim((source_tex:gsub("%s+", " "))),
      hl = with(style, "ProgramavimasMath").hl,
      url = style.url,
      atomic = true,
      math = true,
      display = text:sub(1, 2) == "$$",
      latex = converted == nil and source_tex or nil,
    })
  elseif kind == "inline_link" or kind:match("reference_link$") or kind == "shortcut_link" then
    local label, url
    for child in node:iter_children() do
      if child:type() == "link_text" then label = child end
      if child:type() == "link_destination" then
        url = vim.treesitter.get_node_text(child, source):gsub("^<(.*)>$", "%1")
      end
    end
    if label then walk(label, source, url and with(style, "ProgramavimasLink", url) or style, spans, cell) end
  elseif kind == "image" then
    local alt, url = {}, nil
    for child in node:iter_children() do
      if child:type() == "image_description" then
        local parts = {}
        walk(child, source, { hl = {} }, parts, cell)
        for _, part in ipairs(parts) do table.insert(alt, part.text or "") end
      elseif child:type() == "link_destination" then
        url = vim.treesitter.get_node_text(child, source):gsub("^<(.*)>$", "%1")
      end
    end
    local label = vim.trim(table.concat(alt))
    table.insert(spans, {
      text = label ~= "" and label or labels.image,
      hl = with(style, "ProgramavimasLink").hl,
      url = url,
      atomic = true,
      image = true,
    })
  elseif kind == "backslash_escape" then
    emit(spans, text:sub(2), style)
  elseif kind == "hard_line_break" then
    table.insert(spans, { text = "", hl = {}, brk = true })
  elseif kind == "html_tag" then
    if text:lower():match("^<br%s*/?>$") then
      table.insert(spans, { text = "", hl = {}, brk = true })
    else
      emit(spans, text, style)
    end
  elseif kind == "entity_reference" then
    emit(spans, ENTITIES[text:sub(2, -2)] or text, style)
  elseif kind == "numeric_character_reference" then
    local hex, decimal = text:match("^&#[xX](%x+);$"), text:match("^&#(%d+);$")
    local code = hex and tonumber(hex, 16) or decimal and tonumber(decimal)
    emit(spans, code and code > 0 and vim.fn.nr2char(code) or text, style)
  elseif kind == "uri_autolink" or kind == "email_autolink" then
    local target = text:sub(2, -2)
    emit(spans, target, with(style, "ProgramavimasLink", kind == "email_autolink" and "mailto:" .. target or target))
  else
    walk(node, source, style, spans, cell)
  end
end

--- A node's text as spans: what lies between its named children is plain text.
walk = function(node, source, style, spans, cell)
  local _, _, position = node:start()
  local _, _, stop = node:end_()
  for child in node:iter_children() do
    if child:named() then
      local _, _, from = child:start()
      local _, _, to = child:end_()
      if from > position then emit(spans, source:sub(position + 1, from), style) end
      inline_node(child, source, style, spans, cell)
      position = to
    end
  end
  if stop > position then emit(spans, source:sub(position + 1, stop), style) end
end

---@param text string
---@param cell? boolean
---@return programavimas.Span[]
local function parse_inline(text, cell)
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, "markdown_inline")
  if not ok or not parser then return { { text = text, hl = {} } } end
  local spans = {}
  walk(parser:parse()[1]:root(), text, { hl = {} }, spans, cell or false)
  return spans
end

--- A node's text without the prefixes of the blocks around it (`> `, a list item's indent).
---@param lines string[]
---@param node TSNode
local function clean(lines, node)
  local start_row, start_col, end_row, end_col = node:range()
  local skip = {}
  for child in node:iter_children() do
    if child:type() == "block_continuation" then
      local row, _, _, col = child:range()
      skip[row] = col
    end
  end
  local parts = {}
  for row = start_row, end_row do
    local line = lines[row + 1] or ""
    local from = row == start_row and start_col or (skip[row] or 0)
    local to = row == end_row and end_col or #line
    table.insert(parts, line:sub(from + 1, to))
  end
  return table.concat(parts, "\n")
end

---@param spans programavimas.Span[]
local function text_of(spans)
  local parts = {}
  for _, span in ipairs(spans) do table.insert(parts, span.text) end
  return vim.trim(table.concat(parts))
end

--- Whether every visible span carries `group` (a label: **Pradiniai duomenys**, `duom.txt`).
---@param spans programavimas.Span[]
---@param group string
local function only(spans, group)
  local found = false
  for _, span in ipairs(spans) do
    if span.brk or span.image or span.math or span.url then return false end
    if span.text:match("%S") then
      if not vim.tbl_contains(span.hl, group) then return false end
      found = true
    end
  end
  return found
end

---@param spans programavimas.Span[]
local function paragraph(spans)
  local visible = vim.tbl_filter(function(span)
    return span.brk or span.image or span.math or span.text:match("%S") ~= nil
  end, spans)
  if #visible == 1 and visible[1].math and visible[1].display then return { kind = "math", span = visible[1] } end
  if #visible == 1 and visible[1].image then return { kind = "image", span = visible[1] } end
  return { kind = "paragraph", spans = spans }
end

local function child_of(node, kind)
  for child in node:iter_children() do
    if child:type() == kind then return child end
  end
end

local parse_blocks

---@param node TSNode
---@param source string
local function table_block(node, source)
  local block = { kind = "table", align = {}, rows = {} }
  for row in node:iter_children() do
    local kind = row:type()
    if kind == "pipe_table_header" or kind == "pipe_table_row" then
      local cells = {}
      for cell in row:iter_children() do
        if cell:type() == "pipe_table_cell" then
          table.insert(cells, parse_inline(vim.trim(vim.treesitter.get_node_text(cell, source)), true))
        end
      end
      if kind == "pipe_table_header" then block.header = cells else table.insert(block.rows, cells) end
    elseif kind == "pipe_table_delimiter_row" then
      for cell in row:iter_children() do
        if cell:type() == "pipe_table_delimiter_cell" then
          local left = child_of(cell, "pipe_table_align_left") ~= nil
          local right = child_of(cell, "pipe_table_align_right") ~= nil
          table.insert(block.align, left and right and "center" or right and "right" or "left")
        end
      end
    end
  end
  block.header = block.header or {}
  return block
end

---@param node TSNode
---@param lines string[]
---@param source string
---@param out table[]
parse_blocks = function(node, lines, source, out)
  for child in node:iter_children() do
    local kind = child:type()
    if kind == "section" then
      parse_blocks(child, lines, source, out)
    elseif kind == "paragraph" then
      local inline = child_of(child, "inline")
      if inline then table.insert(out, paragraph(parse_inline(clean(lines, inline)))) end
    elseif kind == "atx_heading" or kind == "setext_heading" then
      local level, inline = 1, child_of(child, "inline")
      for part in child:iter_children() do
        local number = part:type():match("^atx_h(%d)_marker$")
        if number then level = tonumber(number) end
        if part:type() == "setext_h2_underline" then level = 2 end
        if part:type() == "paragraph" then inline = child_of(part, "inline") end
      end
      if inline then table.insert(out, { kind = "heading", level = level, spans = parse_inline(clean(lines, inline)) }) end
    elseif kind == "list" then
      local list = { kind = "list", items = {} }
      for item in child:iter_children() do
        if item:type() == "list_item" then
          for part in item:iter_children() do
            local marker = part:type():match("^list_marker") and vim.treesitter.get_node_text(part, source)
            local number = marker and marker:match("^%s*(%d+)")
            if number and not list.start then list.start = tonumber(number) end
          end
          local blocks = {}
          parse_blocks(item, lines, source, blocks)
          table.insert(list.items, { blocks = blocks })
        end
      end
      table.insert(out, list)
    elseif kind == "fenced_code_block" or kind == "indented_code_block" then
      local language, text = "", ""
      if kind == "fenced_code_block" then
        local info = child_of(child, "info_string")
        language = info and vim.trim(vim.treesitter.get_node_text(info, source)):match("^%S*") or ""
        local content = child_of(child, "code_fence_content")
        text = content and clean(lines, content) or ""
      else
        text = clean(lines, child):gsub("\n    ", "\n"):gsub("^    ", "")
      end
      table.insert(out, { kind = "code", language = language:lower(), text = (text:gsub("\n+$", "")) })
    elseif kind == "block_quote" then
      local quote = { kind = "quote", blocks = {} }
      parse_blocks(child, lines, source, quote.blocks)
      table.insert(out, quote)
    elseif kind == "thematic_break" then
      table.insert(out, { kind = "rule" })
    elseif kind == "pipe_table" then
      table.insert(out, table_block(child, source))
    elseif kind == "html_block" then
      table.insert(out, { kind = "paragraph", spans = { { text = clean(lines, child), hl = {} } } })
    end
  end
end

--- A sample's label (**Pradiniai duomenys** or `duom.txt`) and its data (a `text` code block,
--- or *Tuščia* when empty), as statementToMarkdown writes them.
local function pane_label(block)
  if block and block.kind == "paragraph"
    and (only(block.spans, "ProgramavimasStrong") or only(block.spans, "ProgramavimasCode"))
  then
    return text_of(block.spans)
  end
end

local function pane_data(block)
  if not block then return nil end
  if block.kind == "code" and block.language == "text" then return { text = block.text } end
  if block.kind == "paragraph" and only(block.spans, "ProgramavimasEmphasis") then
    return { empty = text_of(block.spans) }
  end
end

--- Input and output panes in a row become a sample (with its title, **Pavyzdys 2**, before).
---@param blocks table[]
local function samples(blocks)
  local out, i = {}, 1
  while i <= #blocks do
    local input_label, input = pane_label(blocks[i]), pane_data(blocks[i + 1])
    local output_label, output = pane_label(blocks[i + 2]), pane_data(blocks[i + 3])
    if input_label and input and output_label and output then
      local sample = {
        kind = "sample",
        panes = { { label = input_label, data = input }, { label = output_label, data = output } },
      }
      local previous = out[#out]
      if previous and previous.kind == "paragraph" and only(previous.spans, "ProgramavimasStrong") then
        sample.title = text_of(previous.spans)
        table.remove(out)
      end
      table.insert(out, sample)
      i = i + 4
    else
      table.insert(out, blocks[i])
      i = i + 1
    end
  end
  return out
end

--- The Markdown as blocks, or nil when Neovim has no Markdown parser.
---@param text string
---@param words? { image: string }  An image without a description is called this
---@return table[]?
function M.parse(text, words)
  labels = words or { image = "Image" }
  -- A closing fence on the last line closes only when a newline follows it.
  if text:sub(-1) ~= "\n" then text = text .. "\n" end
  local ok, parser = pcall(vim.treesitter.get_string_parser, text, "markdown")
  if not ok or not parser then return nil end
  local parsed, trees = pcall(parser.parse, parser)
  if not parsed or not trees or not trees[1] then return nil end
  local blocks = {}
  parse_blocks(trees[1]:root(), vim.split(text, "\n", { plain = true }), text, blocks)
  return samples(blocks)
end

-- ------------------------------------------------------------------ wrapping

--- Inline spans as lines of at most `width` columns (ui.wrap), an image as its glyph and label.
---@param spans programavimas.Span[]
---@param width integer
---@return programavimas.Segment[][]
function M.wrap(spans, width)
  return ui.wrap(vim.tbl_map(function(span)
    return span.image and vim.tbl_extend("force", span, { text = IMAGE .. " " .. span.text }) or span
  end, spans), width)
end

local segments_width = ui.segments_width

-- ------------------------------------------------------------------ layout

--- Where lines go: a prefix for the first line and one for the rest (a list item's marker and
--- its hanging indent, a quote's bar), inside the frames around it.
---@class programavimas.Frame
---@field parent programavimas.Frame?
---@field first programavimas.Segment[]
---@field rest programavimas.Segment[]
---@field used boolean
---@field width integer
---@field depth integer  Lists around it
---@field item boolean   A list item's own frame
local Frame = {}
Frame.__index = Frame

---@param first programavimas.Segment[]
---@param rest? programavimas.Segment[]
---@param item? boolean
function Frame:nest(first, rest, item)
  rest = rest or first
  return setmetatable({
    parent = self,
    first = first,
    rest = rest,
    used = false,
    width = self.width - math.max(segments_width(first), segments_width(rest)),
    depth = self.depth + (item and 1 or 0),
    item = item or false,
  }, Frame)
end

--- The prefix of the next line.
---@return programavimas.Segment[]
function Frame:take()
  local own = self.used and self.rest or self.first
  self.used = true
  local prefix = self.parent and self.parent:take() or {}
  return vim.list_extend(prefix, own)
end

---@class programavimas.Layout
---@field out programavimas.Lines
---@field margin string
---@field block integer    The block being drawn, counted in document order
---@field anchors table<integer, integer>  Line → block, to keep the reading place on resize

---@param layout programavimas.Layout
---@param frame programavimas.Frame
---@param segments programavimas.Segment[]
local function line_out(layout, frame, segments)
  local out = layout.out
  out:add(layout.margin)
  for _, segment in ipairs(frame:take()) do out:add(segment.text, segment.hl) end
  for _, segment in ipairs(segments) do out:add(segment.text, segment.hl, segment.url) end
  out:nl()
  layout.anchors[out:count()] = layout.block
end

--- An empty line inside the frame: the bars of the quotes around it stay.
local function blank_out(layout, frame)
  local prefix = frame:take()
  while #prefix > 0 and not prefix[#prefix].text:match("%S") do table.remove(prefix) end
  local out = layout.out
  if #prefix > 0 then
    out:add(layout.margin)
    for index, segment in ipairs(prefix) do
      out:add(index == #prefix and (segment.text:gsub("%s+$", "")) or segment.text, segment.hl)
    end
  end
  out:nl()
  layout.anchors[out:count()] = layout.block
end

---@param spans programavimas.Span[]
---@param group string
local function restyle(spans, group)
  return vim.tbl_map(function(span)
    return vim.tbl_extend("force", span, { hl = vim.list_extend({ group }, span.hl) })
  end, spans)
end

--- One line of a band (a code block, a sample's data): `text` from the band's padding,
--- the rest filled to `width`, so the band reads as one block whatever the text's length.
---@param segments programavimas.Segment[]  What the band's line shows (hl under the band)
---@param width integer
---@return programavimas.Segment[]
local function band(segments, width)
  local out = { { text = (" "):rep(PAD), hl = { "ProgramavimasCodeBlock" } } }
  local used = PAD
  for _, segment in ipairs(segments) do
    table.insert(out, { text = segment.text, hl = vim.list_extend({ "ProgramavimasCodeBlock" }, segment.hl or {}) })
    used = used + width_of(segment.text)
  end
  table.insert(out, { text = (" "):rep(math.max(0, width - used)), hl = { "ProgramavimasCodeBlock" } })
  return out
end

---@param text string
local function code_lines(text)
  return vim.split(expand_tabs(text), "\n", { plain = true })
end

--- A band's lines of text as rows of at most `room` cells: the rest of a longer line follows
--- on rows that start with a faint ↪, so nothing runs past the band.
---@param lines string[]
---@param room integer
---@return programavimas.Segment[][]
local function band_rows(lines, room)
  local rows = {}
  for _, line in ipairs(lines) do
    local rest, first = line, true
    repeat
      local limit = math.max(first and room or room - 2, 1)
      local bytes, used = 0, 0
      for char in rest:gmatch(CHAR) do
        local cells = width_of(char)
        if used + cells > limit and bytes > 0 then break end
        bytes, used = bytes + #char, used + cells
      end
      local piece = rest:sub(1, bytes)
      rest = rest:sub(bytes + 1)
      table.insert(rows, first and { { text = piece } } or { { text = "↪ ", hl = { "ProgramavimasFaint" } }, { text = piece } })
      first = false
    until rest == ""
  end
  return rows
end

local render_blocks

local render = {}

function render.paragraph(layout, frame, block)
  for _, line in ipairs(M.wrap(block.spans, frame.width)) do line_out(layout, frame, line) end
end

function render.heading(layout, frame, block)
  local group = block.level <= 2 and "ProgramavimasHeading" or "ProgramavimasStrong"
  for _, line in ipairs(M.wrap(restyle(block.spans, group), frame.width)) do line_out(layout, frame, line) end
end

function render.math(layout, frame, block)
  local span = block.span
  local text = span.latex and vim.trim(span.latex) or span.text
  local inside = frame:nest({ { text = "    " } })
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    if vim.trim(line) ~= "" then line_out(layout, inside, { { text = vim.trim(line), hl = { "ProgramavimasMath" } } }) end
  end
end

function render.image(layout, frame, block)
  local span = block.span
  local lines = M.wrap({ { text = span.text, hl = { "ProgramavimasLink" }, url = span.url } }, frame.width - 2)
  for index, line in ipairs(lines) do
    table.insert(line, 1, { text = index == 1 and IMAGE .. " " or "  ", hl = { "ProgramavimasMuted" }, url = span.url })
    line_out(layout, frame, line)
  end
end

function render.rule(layout, frame)
  line_out(layout, frame, { { text = RULE:rep(frame.width), hl = { "ProgramavimasFaint" } } })
end

function render.code(layout, frame, block)
  local width = frame.width
  local language = not PLAIN[block.language] and (LANGUAGE_NAMES[block.language] or block.language) or nil
  local top = {}
  if language then
    local room = width - PAD - width_of(language) - PAD
    top = { { text = (" "):rep(math.max(0, room)) }, { text = language, hl = { "ProgramavimasMuted" } } }
  end
  line_out(layout, frame, band(top, width))
  for _, row in ipairs(band_rows(code_lines(block.text), width - 2 * PAD)) do line_out(layout, frame, band(row, width)) end
  line_out(layout, frame, band({}, width))
end

--- A sample: its title, then the input and the output beside each other when both fit half the
--- width, else one under the other.
function render.sample(layout, frame, block)
  if block.title then
    line_out(layout, frame, { { text = block.title, hl = { "ProgramavimasStrong" } } })
  end
  local width, gap = frame.width, 3
  local half = math.floor((width - gap) / 2)
  local panes = {}
  -- Side by side, both as wide as the wider one needs (never narrower than a short line).
  local needed = 24
  for index, pane in ipairs(block.panes) do
    local rows = pane.data.text and code_lines(pane.data.text) or nil
    needed = math.max(needed, width_of(pane.label))
    for _, row in ipairs(rows or {}) do needed = math.max(needed, width_of(row) + 2 * PAD) end
    panes[index] = { label = pane.label, rows = rows, empty = pane.data.empty }
  end
  local fits = needed <= half
  half = math.min(half, needed)
  --- A pane's rows for a band `pane_width` wide (an empty sample says so).
  local function rows_of(pane, pane_width)
    if pane.rows then return band_rows(pane.rows, pane_width - 2 * PAD) end
    return { { { text = pane.empty, hl = { "ProgramavimasMuted", "ProgramavimasEmphasis" } } } }
  end

  if fits then
    local labels = {}
    for index, pane in ipairs(panes) do
      table.insert(labels, { text = pane.label, hl = { "ProgramavimasMuted" } })
      if index == 1 then table.insert(labels, { text = (" "):rep(half - width_of(pane.label) + gap) }) end
    end
    line_out(layout, frame, labels)
    local left, right = rows_of(panes[1], half), rows_of(panes[2], half)
    local height = math.max(#left, #right)
    for index = 0, height + 1 do
      line_out(layout, frame, vim.list_extend(
        vim.list_extend(band(left[index] or {}, half), { { text = (" "):rep(gap) } }),
        band(right[index] or {}, half)
      ))
    end
    return
  end
  for side, pane in ipairs(panes) do
    if side > 1 then blank_out(layout, frame) end
    line_out(layout, frame, { { text = pane.label, hl = { "ProgramavimasMuted" } } })
    line_out(layout, frame, band({}, width))
    for _, row in ipairs(rows_of(pane, width)) do line_out(layout, frame, band(row, width)) end
    line_out(layout, frame, band({}, width))
  end
end

--- A quote: a bar down its side; a note, warning or hint (a quote that starts with the
--- server's label) in the label's colour, the label on the first line.
function render.quote(layout, frame, block)
  local blocks = block.blocks
  local first = blocks[1]
  local tone = first and first.kind == "paragraph" and only(first.spans, "ProgramavimasStrong")
    and TONES[text_of(first.spans)] or nil
  local inside = frame:nest({ { text = BAR .. " ", hl = { tone or "ProgramavimasQuote" } } })
  if tone then
    line_out(layout, inside, { { text = text_of(first.spans), hl = { "ProgramavimasStrong", tone } } })
    render_blocks(layout, inside, vim.list_slice(blocks, 2))
  else
    render_blocks(layout, inside, blocks)
  end
end

---@param item { blocks: table[] }
local function compact(item)
  if #item.blocks == 0 or item.blocks[1].kind ~= "paragraph" then return #item.blocks == 0 end
  for index = 2, #item.blocks do
    if item.blocks[index].kind ~= "list" then return false end
  end
  return true
end

--- Bullets by depth, or numbers aligned on their dots; text hangs under the first line's text.
function render.list(layout, frame, block)
  local markers, marker_width = {}, 0
  for index in ipairs(block.items) do
    local marker = block.start and ("%d."):format(block.start + index - 1)
      or BULLETS[frame.depth % #BULLETS + 1]
    markers[index] = marker
    marker_width = math.max(marker_width, width_of(marker))
  end
  for index, item in ipairs(block.items) do
    if index > 1 and not compact(block.items[index - 1]) then blank_out(layout, frame) end
    local marker = (" "):rep(marker_width - width_of(markers[index])) .. markers[index] .. " "
    local inside = frame:nest(
      { { text = marker, hl = { "ProgramavimasListMarker" } } },
      { { text = (" "):rep(marker_width + 1) } },
      true
    )
    render_blocks(layout, inside, item.blocks)
  end
end

--- The header row in bold.
local function restyle_cells(cells)
  return vim.tbl_map(function(cell) return restyle(cell, "ProgramavimasStrong") end, cells)
end

--- A pipe table: columns aligned as the delimiter row says, a rule under the header, `│`
--- between columns. Columns too wide for the frame are narrowed, their cells wrapped.
function render.table(layout, frame, block)
  -- The header sets the columns; a row's extra cells are left out, as GFM does.
  local columns = #block.header
  if columns == 0 then return end
  local rows = { restyle_cells(block.header) }
  for _, row in ipairs(block.rows) do table.insert(rows, row) end

  local natural, least = {}, {}
  for column = 1, columns do
    natural[column], least[column] = 1, 1
    for _, row in ipairs(rows) do
      local spans = row[column] or {}
      for _, line in ipairs(M.wrap(spans, math.huge)) do
        natural[column] = math.max(natural[column], segments_width(line))
      end
      for _, span in ipairs(spans) do
        for word in span.text:gmatch("%S+") do least[column] = math.max(least[column], math.min(width_of(word), 12)) end
      end
    end
  end
  local separator = " │ "
  local available = frame.width - width_of(separator) * (columns - 1)
  local widths = vim.deepcopy(natural)
  local total = 0
  for _, value in ipairs(widths) do total = total + value end
  while total > available do
    local widest
    for column = 1, columns do
      if widths[column] > least[column] and (not widest or widths[column] > widths[widest]) then widest = column end
    end
    if not widest then break end
    widths[widest] = widths[widest] - 1
    total = total - 1
  end

  local cells = {}
  local tall = false
  for index, row in ipairs(rows) do
    cells[index] = {}
    for column = 1, columns do
      cells[index][column] = M.wrap(row[column] or {}, widths[column])
      if #cells[index][column] > 1 then tall = true end
    end
  end
  local function rule(cross)
    local parts = {}
    for column = 1, columns do table.insert(parts, RULE:rep(widths[column])) end
    line_out(layout, frame, { { text = table.concat(parts, RULE .. cross .. RULE), hl = { "ProgramavimasFaint" } } })
  end
  for index in ipairs(rows) do
    if index == 2 then rule("┼") elseif index > 2 and tall then rule("┼") end
    local height = 1
    for column = 1, columns do height = math.max(height, #cells[index][column]) end
    for line_index = 1, height do
      local line = {}
      for column = 1, columns do
        if column > 1 then table.insert(line, { text = separator, hl = { "ProgramavimasFaint" } }) end
        local content = cells[index][column][line_index] or {}
        local room = widths[column] - segments_width(content)
        local align = block.align[column] or "left"
        local before = align == "right" and room or align == "center" and math.floor(room / 2) or 0
        if before > 0 then table.insert(line, { text = (" "):rep(before) }) end
        vim.list_extend(line, content)
        if column < columns and room - before > 0 then table.insert(line, { text = (" "):rep(room - before) }) end
      end
      line_out(layout, frame, line)
    end
  end
end

---@param layout programavimas.Layout
---@param frame programavimas.Frame
---@param blocks table[]
render_blocks = function(layout, frame, blocks)
  for index, block in ipairs(blocks) do
    -- A list right under its item's text stays with it.
    local joined = index > 1 and frame.item and block.kind == "list" and blocks[index - 1].kind == "paragraph"
    if index > 1 and not joined then blank_out(layout, frame) end
    layout.block = layout.block + 1
    render[block.kind](layout, frame, block)
  end
end

---@class programavimas.MarkdownOptions
---@field width integer   Columns for the text, after the margin
---@field margin? string  Before every line
---@field labels? { image: string }

--- Draws Markdown into `out`. Answers the line → block anchors, or nil (nothing drawn) when
--- Neovim has no Markdown parser.
---@param out programavimas.Lines
---@param text string
---@param options programavimas.MarkdownOptions
---@return table<integer, integer>?
function M.render(out, text, options)
  local blocks = M.parse(text, options.labels)
  if not blocks then return nil end
  local layout = { out = out, margin = options.margin or "", block = 0, anchors = {} }
  local root = setmetatable({ first = {}, rest = {}, used = false, width = options.width, depth = 0, item = false }, Frame)
  render_blocks(layout, root, blocks)
  return layout.anchors
end

return M
