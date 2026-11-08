-- The caller's courses: a sidebar (courses → topics with their deadlines → problems with the
-- web's status glyphs) and the problem picker. Only the viewer's own progress is ever shown:
-- the API returns nothing about other students.

local api = require("programavimas.api")
local async = require("programavimas.async")
local config = require("programavimas.config")
local i18n = require("programavimas.i18n")
local time = require("programavimas.time")
local ui = require("programavimas.ui")
local t = i18n.t

local M = {}

local BUFFER = "programavimas://courses"

---@type table[]?  The courses as last loaded
M.cache = nil
local loading = false
local load_error ---@type string?
--- Expanded nodes by id (courses start expanded, topics collapsed).
local expanded = {}
--- Line (1-based) → node.
local line_nodes = {}

---@class programavimas.Located
---@field course table
---@field topic table?
---@field problem table
---@field layout programavimas.Layout

--- Every problem of a course with its layout positions (topics and problems in course order),
--- as the VS Code extension numbers them, so both make the same folders.
---@param course table
---@return programavimas.Located[]
function M.locate_all(course)
  local located, topic_position = {}, 0
  for _, section in ipairs(course.topics) do
    if section.topic then topic_position = topic_position + 1 end
    local position = topic_position
    for index, problem in ipairs(section.problems or {}) do
      table.insert(located, {
        course = course,
        topic = section.topic,
        problem = problem,
        layout = {
          course = { title = course.title },
          topic = section.topic and { position = position, title = section.topic.title } or nil,
          problem = { position = index, title = problem.title },
        },
      })
    end
  end
  return located
end

--- Loads the courses (inside a task). Returns them or nil after reporting why.
---@param force? boolean
function M.load(force)
  if M.cache and not force then return M.cache end
  loading = true
  load_error = nil
  M.redraw()
  local courses, err = api.courses()
  loading = false
  if courses then
    M.cache = courses
  else
    load_error = ui.api_message(err)
  end
  M.redraw()
  return courses, err
end

--- A problem's place in the courses (loading them when needed). Inside a task.
---@return programavimas.Located?
function M.locate(course_id, problem_id)
  local function find()
    for _, course in ipairs(M.cache or {}) do
      if course.id == course_id then
        for _, entry in ipairs(M.locate_all(course)) do
          if entry.problem.id == problem_id then return entry end
        end
      end
    end
  end
  local found = find()
  if found then return found end
  M.load(true)
  return find()
end

--- Updates one problem's status after a run or submission, without reloading everything.
function M.update_status(course_id, problem_id, status)
  for _, course in ipairs(M.cache or {}) do
    if course.id == course_id then
      for _, entry in ipairs(M.locate_all(course)) do
        if entry.problem.id == problem_id then entry.problem.status = status end
      end
    end
  end
  M.redraw()
end

function M.forget()
  M.cache = nil
  load_error = nil
  M.redraw()
end

-- ------------------------------------------------------------------ the sidebar

---@param out programavimas.Lines
---@param topic table
local function topic_description(out, topic, hidden)
  if topic.mode == "test" then out:add("  " .. t("courses.topicMode.test"), "ProgramavimasAccent") end
  local due = time.parse(topic.dueAt)
  if due then
    out:add("  " .. time.due_label(due), due < os.time() and "ProgramavimasDanger" or "ProgramavimasMuted")
  end
  if hidden > 0 then out:add("  " .. t("courses.hidden", { count = hidden }), "ProgramavimasMuted") end
end

---@param out programavimas.Lines
---@param problem table
---@param indent string
local function problem_line(out, problem, indent)
  local glyph = ui.status_glyph(problem.status)
  out:add(indent):add(glyph.icon, glyph.hl):add(" ")
  out:add(problem.title, problem.status.kind == "locked" and "ProgramavimasMuted" or nil)
  if problem.type == "spreadsheet" then
    out:add("  Excel", "ProgramavimasMuted")
  elseif problem.status.kind == "attempted" then
    out:add("  " .. t("courses.passed", { passed = problem.status.passed, total = problem.status.total }), "ProgramavimasMuted")
  end
  out:nl()
end

---@return programavimas.Lines
function M.build()
  line_nodes = {}
  local icons = config.options.icons
  local out = ui.lines()
  local me = require("programavimas.account").me
  out:add(t("view.courses"), "ProgramavimasTitle")
  if me then out:add(" · " .. me.name, "ProgramavimasMuted") end
  out:nl():nl()
  if not require("programavimas.account").signed_in() then
    out:line(t("auth.notSignedIn"), "ProgramavimasMuted")
    return out
  end
  if load_error then out:line(load_error, "ProgramavimasDanger") end
  if not M.cache then
    if loading then out:line(t("courses.loading"), "ProgramavimasMuted") end
    return out
  end
  if #M.cache == 0 then out:line(t("courses.empty"), "ProgramavimasMuted") end
  for _, course in ipairs(M.cache) do
    local open = expanded[course.id] ~= false
    out:add((open and icons.expanded or icons.collapsed) .. " ", "ProgramavimasMuted"):line(course.title, "ProgramavimasHeading")
    line_nodes[out:count()] = { kind = "course", course = course }
    if open then
      for _, section in ipairs(course.topics) do
        if section.topic then
          local topic = section.topic
          local topic_open = expanded[topic.id] == true
          out:add("  " .. (topic_open and icons.expanded or icons.collapsed) .. " ", "ProgramavimasMuted")
          out:add(topic.title)
          topic_description(out, topic, section.hiddenCount or 0)
          out:nl()
          line_nodes[out:count()] = { kind = "topic", course = course, topic = topic }
          if topic_open then
            for _, problem in ipairs(section.problems or {}) do
              problem_line(out, problem, "      ")
              line_nodes[out:count()] = { kind = "problem", course = course, topic = topic, problem = problem }
            end
          end
        else
          for _, problem in ipairs(section.problems or {}) do
            problem_line(out, problem, "    ")
            line_nodes[out:count()] = { kind = "problem", course = course, problem = problem }
          end
        end
      end
    end
  end
  out:nl():line(t("help.hint"), "ProgramavimasFaint")
  return out
end

function M.redraw()
  local buf = vim.fn.bufnr(BUFFER)
  if buf == -1 or not vim.api.nvim_buf_is_valid(buf) then return end
  local out = M.build()
  ui.render(buf, out.lines, out.marks)
end

local function node_at_cursor()
  return line_nodes[vim.api.nvim_win_get_cursor(0)[1]]
end

--- Opens a problem: Excel tasks in the browser, programming problems in the editor.
---@param node table
local function open_problem(node)
  if node.problem.type == "spreadsheet" then
    ui.notify(t("courses.spreadsheet"))
    vim.ui.open(api.problem_page(node.course.id, node.problem.id))
    return
  end
  require("programavimas.problems").open(node.course.id, node.problem.id)
end

---@param node table
---@param open? boolean  nil toggles
local function set_open(node, open)
  local id = node.kind == "course" and node.course.id or node.topic.id
  local current = node.kind == "course" and expanded[id] ~= false or expanded[id] == true
  if open == nil then open = not current end
  expanded[id] = open
  M.redraw()
end

local function activate()
  local node = node_at_cursor()
  if not node then return end
  if node.kind == "problem" then open_problem(node) else set_open(node) end
end

local function buffer()
  local buf = ui.scratch(BUFFER, "programavimas")
  if vim.b[buf].programavimas_keys then return buf end
  vim.b[buf].programavimas_keys = true
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end
  map("<CR>", activate, "Open problem or expand")
  map("o", activate, "Open problem or expand")
  map("<2-LeftMouse>", activate, "Open problem or expand")
  map("l", function()
    local node = node_at_cursor()
    if node and node.kind ~= "problem" then set_open(node, true) end
  end, "Expand")
  map("h", function()
    local node = node_at_cursor()
    if not node then return end
    if node.kind == "problem" and node.topic then
      set_open({ kind = "topic", topic = node.topic, course = node.course }, false)
    elseif node.kind ~= "problem" then
      set_open(node, false)
    end
  end, "Collapse")
  map("r", function() async.run(function() M.load(true) end) end, "Refresh")
  map("gx", function()
    local node = node_at_cursor()
    if node and node.problem then vim.ui.open(api.problem_page(node.course.id, node.problem.id)) end
  end, "Open in browser")
  map("P", function()
    local node = node_at_cursor()
    if node then require("programavimas.problems").prepare_course(node.course) end
  end, "Create course folders")
  map("q", function() M.close() end, "Close")
  map("?", function() ui.notify(t("courses.help")) end, "Keys")
  return buf
end

function M.close()
  local buf = vim.fn.bufnr(BUFFER)
  local win = buf ~= -1 and ui.window_of(buf) or nil
  if win and #vim.api.nvim_tabpage_list_wins(0) > 1 then vim.api.nvim_win_close(win, false) end
end

function M.open()
  local buf = buffer()
  local win = ui.window_of(buf)
  if not win then
    local side = config.options.courses.position == "right" and "botright" or "topleft"
    vim.cmd(("%s vertical %dsplit"):format(side, config.options.courses.width))
    win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, buf)
    for option, value in pairs({
      number = false,
      relativenumber = false,
      signcolumn = "no",
      foldcolumn = "0",
      wrap = false,
      winfixwidth = true,
      cursorline = true,
      spell = false,
    }) do
      vim.wo[win][option] = value
    end
  end
  vim.api.nvim_set_current_win(win)
  M.redraw()
  if not M.cache and require("programavimas.account").signed_in() then
    async.run(function()
      require("programavimas.account").load()
      M.load()
    end)
  end
end

function M.toggle()
  local buf = vim.fn.bufnr(BUFFER)
  if buf ~= -1 and ui.window_of(buf) then M.close() else M.open() end
end

--- Reloads the courses when the sidebar is showing (after signing in, for example).
function M.refresh()
  local buf = vim.fn.bufnr(BUFFER)
  if buf ~= -1 and ui.window_of(buf) then
    async.run(function() M.load(true) end)
  else
    M.cache = nil
  end
end

-- ------------------------------------------------------------------ the picker

--- Every problem of every course in one list (`vim.ui.select`, so Telescope, fzf-lua or
--- snacks show it when they replace the picker).
function M.pick()
  async.run(function()
    if not require("programavimas.account").signed_in() then return ui.notify(t("auth.notSignedIn")) end
    require("programavimas.account").load()
    local courses, err = M.load()
    if not courses then return ui.error(ui.api_message(err)) end
    local items = {}
    for _, course in ipairs(courses) do
      for _, entry in ipairs(M.locate_all(course)) do table.insert(items, entry) end
    end
    if #items == 0 then return ui.notify(t("courses.empty")) end
    local choice = async.await(function(done)
      vim.ui.select(items, {
        prompt = t("open.prompt"),
        format_item = function(entry)
          local glyph = ui.status_glyph(entry.problem.status)
          local where = { entry.course.title, entry.topic and entry.topic.title or nil }
          return ("%s %s  ·  %s"):format(glyph.icon, entry.problem.title, table.concat(where, " › "))
        end,
      }, done)
    end)
    if choice then open_problem({ course = choice.course, problem = choice.problem }) end
  end)
end

return M
