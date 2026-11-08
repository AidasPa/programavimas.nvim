-- The statement beside the editor: the title, the course and topic, the problem's facts
-- (status, difficulty, limits, I/O, languages, deadline, attempts left), then the statement
-- itself. By default it is drawn as text (markdown.lua: the server's `statementMarkdown` with
-- its formulas, samples and tables laid out at the window's width, drawn again when the
-- window's width changes); with `statement = { render = "markdown" }` it is a Markdown buffer
-- instead, for render-markdown.nvim, markview.nvim and the like.

local config = require("programavimas.config")
local i18n = require("programavimas.i18n")
local paths = require("programavimas.paths")
local time = require("programavimas.time")
local ui = require("programavimas.ui")
local t = i18n.t

local M = {}

-- Before every line of text; and the widest a line of text gets, for reading.
local MARGIN = "  "
local MEASURE = 100

---@param detail table
local function name_of(detail)
  return ("programavimas://statement/%s/%s"):format(detail.course.id, detail.id)
end

local function builtin() return config.options.statement.render ~= "markdown" end

-- Between the facts of a row.
local GAP = "   "

---@alias programavimas.Fact { [1]: string, [2]: string? }[]  Pieces and their highlight (nil: the normal colour)

--- A message in pieces: its words muted, the values put in it in `value_hl` (nil: the normal
--- colour, the brightest text), so the values read first.
---@param key string
---@param params table<string, any>
---@param value_hl? string
---@return programavimas.Fact
local function message(key, params, value_hl)
  return vim.tbl_map(function(part)
    if part.value then return { part.text, value_hl } end
    return { part.text, "ProgramavimasMuted" }
  end, i18n.parts(key, params))
end

---@param bytes integer
local function memory(bytes)
  -- As the web writes it (features/problems/rules.ts): whole gigabytes as GB, else MB.
  local mib = bytes / 1048576
  if mib >= 1024 and (mib / 1024) % 1 == 0 then return message("statement.gigabytes", { gb = math.floor(mib / 1024) }) end
  return message("statement.megabytes", { mb = math.max(1, math.floor(mib + 0.5)) })
end

--- The problem's facts in two rows: where you stand (status, difficulty, deadline, attempts
--- left), then the problem (time and memory limits, input and output, languages). Each fact
--- starts with its icon; icons and words are muted, values in the normal colour, and colour
--- only where it means something (a deadline soon or past, no attempts left).
---@param detail table
---@param markdown boolean  File names as code spans
---@return programavimas.Fact[][]
local function facts(detail, markdown)
  local icons = config.options.icons
  local function fact(icon, pieces)
    return vim.list_extend({ { icons[icon] .. " ", "ProgramavimasMuted" } }, pieces)
  end
  local standing, problem = {}, {}

  local glyph = ui.status_glyph(detail.status)
  table.insert(standing, { { glyph.icon .. " " .. glyph.label, glyph.hl } })
  local meter = ui.difficulty(detail.difficulty)
  if meter then
    local bars = {}
    for index, bar in ipairs(vim.fn.split(meter.text, "\\zs")) do
      table.insert(bars, { bar, index <= meter.filled and "ProgramavimasAccent" or "ProgramavimasFaint" })
    end
    table.insert(standing, bars)
  end
  local at = detail.topic and time.parse(detail.topic.dueAt)
  if at then
    local due = time.due(at)
    -- A solved problem's deadline no longer presses.
    local hl = detail.status.kind == "complete" and "ProgramavimasMuted"
      or due.tone == "danger" and "ProgramavimasDanger"
      or due.tone == "warning" and "ProgramavimasWarning"
      or nil
    if due.later then
      table.insert(standing, fact("deadline", { { due.date, hl }, { ", " .. due.later, "ProgramavimasMuted" } }))
    else
      table.insert(standing, fact("deadline", { { due.text, hl } }))
    end
  end
  if detail.attempts and detail.attempts.total then
    if detail.attempts.left > 0 then
      table.insert(standing, fact("attempts", message("statement.attempts", {
        left = detail.attempts.left,
        total = detail.attempts.total,
      })))
    else
      table.insert(standing, fact("attempts", { { t("attempts.none"), "ProgramavimasWarning" } }))
    end
  end

  local seconds = i18n.number(detail.limits.timeMs / 1000)
  table.insert(problem, fact("time_limit", message("statement.seconds", { seconds = seconds })))
  table.insert(problem, fact("memory_limit", memory(detail.limits.memoryBytes)))
  if detail.io.kind == "files" then
    local quote = markdown and "`" or ""
    table.insert(problem, fact("io", {
      { quote .. detail.io.input .. quote },
      { " → ", "ProgramavimasMuted" },
      { quote .. detail.io.output .. quote },
    }))
  else
    table.insert(problem, fact("io", { { t("statement.stdio") } }))
  end
  if #(detail.languages or {}) > 0 then
    local names = {}
    for index, language in ipairs(detail.languages) do
      if index > 1 then table.insert(names, { ", ", "ProgramavimasMuted" }) end
      if paths.is_editor_language(language.code) then
        table.insert(names, { language.name })
      else
        vim.list_extend(names, message("statement.languageElsewhere", { name = language.name }))
      end
    end
    table.insert(problem, fact("languages", names))
  end
  return { standing, problem }
end

---@param detail table
local function breadcrumb(detail)
  local parts = { detail.course.title, detail.topic and detail.topic.title or nil }
  return table.concat(vim.tbl_filter(function(part) return part ~= nil end, parts), " › ")
end

--- The Markdown buffer's text, for Markdown renderers: a heading, the facts on one line, a
--- thematic break and the server's Markdown as it is.
---@param detail table
---@return programavimas.Lines
local function build_markdown(detail)
  local out = ui.lines()
  out:line("# " .. detail.title):nl()
  out:line(breadcrumb(detail), "ProgramavimasMuted"):nl()
  for _, row in ipairs(facts(detail, true)) do
    for index, fact in ipairs(row) do
      if index > 1 then out:add(" · ", "ProgramavimasFaint") end
      for _, piece in ipairs(fact) do out:add(piece[1], piece[2]) end
    end
    out:nl():nl()
  end
  out:line("---"):nl()
  if detail.statementMarkdown then
    for _, line in ipairs(vim.split(vim.trim(detail.statementMarkdown), "\n", { plain = true })) do
      out:line(line)
    end
  else
    out:line("> " .. t("statement.notReady"))
  end
  return out
end

--- The statement drawn for a window `width` columns wide: the header, a faint rule across the
--- window, and the statement at a readable measure.
---@param detail table
---@param width? integer  The window's text columns (80 when unknown)
---@return programavimas.Lines out, table<integer, integer> anchors  Line → statement block
function M.build(detail, width)
  if not builtin() then return build_markdown(detail), {} end
  width = width or 80
  local measure = math.max(20, math.min(width - #MARGIN - 1, MEASURE))
  local markdown = require("programavimas.markdown")
  local out = ui.lines()

  out:nl()
  for _, line in ipairs(ui.wrap({ { text = detail.title, hl = { "ProgramavimasTitle" } } }, measure)) do
    out:add(MARGIN)
    for _, piece in ipairs(line) do out:add(piece.text, piece.hl) end
    out:nl()
  end
  out:add(MARGIN):line(breadcrumb(detail), "ProgramavimasMuted"):nl()

  -- The facts, each row wrapped between facts, never inside one.
  for _, row in ipairs(facts(detail, false)) do
    local used = 0
    for _, fact in ipairs(row) do
      local cells = 0
      for _, piece in ipairs(fact) do cells = cells + vim.api.nvim_strwidth(piece[1]) end
      if used > 0 and used + #GAP + cells > measure then
        out:nl()
        used = 0
      end
      out:add(used == 0 and MARGIN or GAP)
      if used > 0 then used = used + #GAP end
      for _, piece in ipairs(fact) do out:add(piece[1], piece[2]) end
      used = used + cells
    end
    out:nl()
  end
  out:line(("─"):rep(math.max(width, 1)), "ProgramavimasFaint"):nl()

  local anchors
  if detail.statementMarkdown and vim.trim(detail.statementMarkdown) ~= "" then
    anchors = markdown.render(out, detail.statementMarkdown, {
      width = measure,
      margin = MARGIN,
      labels = { image = t("statement.image") },
    })
    if not anchors then
      -- No Markdown parser in this Neovim: the text as it came.
      for _, line in ipairs(vim.split(vim.trim(detail.statementMarkdown), "\n", { plain = true })) do
        out:line(MARGIN .. line)
      end
    end
  else
    out:add(MARGIN):line(t("statement.notReady"), "ProgramavimasMuted")
  end
  return out, anchors or {}
end

---@type table<integer, table>  buffer → problem detail
M.details = {}
--- What each statement buffer shows: the width it was drawn for, its links, its anchors.
---@type table<integer, { width: integer, links: programavimas.Link[], anchors: table<integer, integer> }>
local views = {}

--- The line of a block after drawing again: the same line of the same block, as near as it
--- has.
---@param before table<integer, integer>
---@param after table<integer, integer>
---@param line integer
---@param count integer  Lines after
local function relocate(before, after, line, count)
  local block = before[line]
  if not block then return math.min(line, count) end
  local first = line
  while before[first - 1] == block do first = first - 1 end
  local start, stop
  for index = 1, count do
    if after[index] == block then
      start = start or index
      stop = index
    end
  end
  if not start then return math.min(line, count) end
  return math.min(start + line - first, stop)
end

--- Draws a statement buffer for the width of the window showing it, keeping the reading place.
---@param buf integer
---@param win? integer
local function draw(buf, win)
  local detail = M.details[buf]
  if not detail or not vim.api.nvim_buf_is_valid(buf) then return end
  win = win or vim.fn.win_findbuf(buf)[1]
  local previous = views[buf]
  local width = win and ui.text_width(win) or previous and previous.width or 80
  local place = win and previous and vim.api.nvim_win_call(win, vim.fn.winsaveview) or nil
  local out, anchors = M.build(detail, width)
  ui.render(buf, out.lines, out.marks)
  views[buf] = { width = width, links = out.links, anchors = anchors }
  ui.drawn(buf, width)
  if place and previous then
    local count = #out.lines
    local cursor = relocate(previous.anchors, anchors, place.lnum, count)
    local top = relocate(previous.anchors, anchors, place.topline, count)
    vim.api.nvim_win_call(win, function()
      vim.fn.winrestview({
        lnum = cursor,
        col = cursor == place.lnum and place.col or 0,
        topline = math.min(top, cursor),
      })
    end)
  end
end

--- The link under the cursor, or the line's only link.
---@param buf integer
---@return string?
local function link_at_cursor(buf)
  local view = views[buf]
  if not view then return nil end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local on_line = {}
  for _, link in ipairs(view.links) do
    if link.line == row - 1 then
      if col >= link.col and col < link.end_col then return link.url end
      on_line[link.url] = true
    end
  end
  local urls = vim.tbl_keys(on_line)
  return #urls == 1 and urls[1] or nil
end

---@param buf integer
local function open_link(buf)
  local url = link_at_cursor(buf)
  -- Only web and mail links, as the server writes them.
  if url and (url:match("^https?://") or url:match("^mailto:")) then vim.ui.open(url) end
end

---@param win integer
local function window_options(win)
  local options = {
    number = false,
    relativenumber = false,
    signcolumn = "no",
    foldcolumn = "0",
    spell = false,
    wrap = true,
  }
  if builtin() then
    -- Lines are already wrapped; a code line too long for the window wraps under itself.
    options.linebreak = false
    options.breakindent = true
    options.list = false
    options.cursorline = false
    options.colorcolumn = ""
    options.conceallevel = 0
    options.statuscolumn = ""
  else
    options.linebreak = true
  end
  for option, value in pairs(options) do vim.wo[win][0][option] = value end
end

--- Shows a problem's statement, reusing its window or the statement window if one is open.
---@param detail table
---@param focus? boolean
function M.show(detail, focus)
  local buf = ui.scratch(name_of(detail), builtin() and "programavimas-statement" or "markdown")
  M.details[buf] = detail
  if not vim.b[buf].programavimas_keys then
    vim.b[buf].programavimas_keys = true
    local function map(lhs, fn, desc)
      vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
    end
    map("o", function() require("programavimas.problems").open(detail.course.id, detail.id) end, "Open solution")
    map("gb", function() vim.ui.open(M.details[buf].webUrl) end, "Open in browser")
    map("r", function() require("programavimas.problems").reload(detail.course.id, detail.id) end, "Refresh")
    map("?", function() ui.notify(t(builtin() and "statement.keys" or "statement.help")) end, "Keys")
    map("q", function()
      local win = ui.window_of(buf)
      if win and #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.api.nvim_win_close(win, false) end
    end, "Close")
    if builtin() then
      map("<CR>", function() open_link(buf) end, "Open the link")
      map("gx", function() open_link(buf) end, "Open the link")
      -- Lines are wrapped for the window: drawn again when its width changes.
      ui.follow_width(buf, function(win) draw(buf, win) end)
    end
  end

  local win = ui.window_of(buf)
  if not win then
    -- Another problem's statement window is reused, so statements do not pile up.
    for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      if vim.b[vim.api.nvim_win_get_buf(candidate)].programavimas_statement then win = candidate end
    end
  end
  local current = vim.api.nvim_get_current_win()
  if not win then
    vim.cmd("rightbelow vsplit")
    win = vim.api.nvim_get_current_win()
  end
  vim.api.nvim_win_set_buf(win, buf)
  vim.b[buf].programavimas_statement = true
  window_options(win)
  draw(buf, win)
  if not focus and vim.api.nvim_win_is_valid(current) then vim.api.nvim_set_current_win(current) end
end

--- Closes every statement: on signing out or in as someone else, so the next person at a
--- shared computer sees none of the previous account's status or attempts.
function M.forget()
  for buf in pairs(M.details) do
    if vim.api.nvim_buf_is_valid(buf) then
      for _, win in ipairs(vim.fn.win_findbuf(buf)) do
        if #vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win)) > 1 then
          vim.api.nvim_win_close(win, true)
        end
      end
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  M.details = {}
  views = {}
end

--- Updates a statement already shown (after a run changed the status or attempts).
---@param detail table
function M.update(detail)
  local buf = vim.fn.bufnr(name_of(detail))
  if buf == -1 then return end
  M.details[buf] = detail
  draw(buf)
end

return M
