-- The statement beside the editor: a Markdown buffer (so Tree-sitter highlighting and any
-- Markdown renderer apply) with the title, the problem's facts on one line (status,
-- difficulty, limits, I/O, languages, deadline, attempts left), then the statement as the
-- server renders it (`statementMarkdown`: formulas as LaTeX, images and wiki links as URLs).

local config = require("programavimas.config")
local i18n = require("programavimas.i18n")
local paths = require("programavimas.paths")
local time = require("programavimas.time")
local ui = require("programavimas.ui")
local t = i18n.t

local M = {}

---@param detail table
local function name_of(detail)
  return ("programavimas://statement/%s/%s"):format(detail.course.id, detail.id)
end

---@param detail table
---@return programavimas.Lines
function M.build(detail)
  local out = ui.lines()
  out:line("# " .. detail.title):nl()
  out:line(table.concat(vim.tbl_filter(function(part) return part ~= nil end, {
    detail.course.title,
    detail.topic and detail.topic.title or nil,
  }), " · "), "ProgramavimasMuted")
  out:nl()

  local function sep() out:add(" · ", "ProgramavimasFaint") end
  local glyph = ui.status_glyph(detail.status)
  out:add(glyph.icon .. " " .. glyph.label, glyph.hl)
  local meter = ui.difficulty(detail.difficulty)
  if meter then
    sep()
    local bars = vim.fn.split(meter.text, "\\zs")
    for index, bar in ipairs(bars) do
      out:add(bar, index <= meter.filled and "ProgramavimasAccent" or "ProgramavimasFaint")
    end
  end
  sep()
  out:add(t("statement.timeLimit", { seconds = (("%.1f"):format(detail.limits.timeMs / 1000):gsub("%.0$", "")) }))
  sep()
  out:add(t("statement.memoryLimit", { mb = math.floor(detail.limits.memoryBytes / 1048576) }))
  sep()
  if detail.io.kind == "files" then
    out:add("`" .. detail.io.input .. "` → `" .. detail.io.output .. "`")
  else
    out:add(t("statement.stdio"))
  end
  if #(detail.languages or {}) > 0 then
    sep()
    local names = vim.tbl_map(function(language)
      return paths.is_editor_language(language.code) and language.name
        or t("statement.languageElsewhere", { name = language.name })
    end, detail.languages)
    out:add(table.concat(names, ", "))
  end
  local due = detail.topic and time.parse(detail.topic.dueAt)
  if due then
    sep()
    out:add(time.due_label(due), due < os.time() and "ProgramavimasDanger" or nil)
  end
  if detail.attempts and detail.attempts.total then
    sep()
    if detail.attempts.left > 0 then
      out:add(t("attempts.short", { left = detail.attempts.left, total = detail.attempts.total }))
    else
      out:add(t("attempts.none"), "ProgramavimasWarning")
    end
  end
  out:nl():nl()
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

---@type table<integer, table>  buffer → problem detail
M.details = {}

--- Shows a problem's statement, reusing its window or the statement window if one is open.
---@param detail table
---@param focus? boolean
function M.show(detail, focus)
  local buf = ui.scratch(name_of(detail), "markdown")
  M.details[buf] = detail
  local out = M.build(detail)
  ui.render(buf, out.lines, out.marks)
  if not vim.b[buf].programavimas_keys then
    vim.b[buf].programavimas_keys = true
    local function map(lhs, fn, desc)
      vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
    end
    map("o", function() require("programavimas.problems").open(detail.course.id, detail.id) end, "Open solution")
    map("gb", function() vim.ui.open(detail.webUrl) end, "Open in browser")
    map("r", function() require("programavimas.problems").reload(detail.course.id, detail.id) end, "Refresh")
    map("?", function() ui.notify(t("statement.help")) end, "Keys")
    map("q", function()
      local win = ui.window_of(buf)
      if win and #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.api.nvim_win_close(win, false) end
    end, "Close")
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
  vim.wo[win].wrap = true
  vim.wo[win].linebreak = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].spell = false
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
end

--- Updates a statement already shown (after a run changed the status or attempts).
---@param detail table
function M.update(detail)
  local buf = vim.fn.bufnr(name_of(detail))
  if buf == -1 then return end
  M.details[buf] = detail
  local out = M.build(detail)
  ui.render(buf, out.lines, out.marks)
end

return M
