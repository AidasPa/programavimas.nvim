-- Solution folders in the folder the student chose (paths.lua has the layout, shared with the
-- VS Code extension). Local files are the drafts, kept in step with the server's copy by
-- drafts.lua: this module creates missing folders and files and never overwrites, renames,
-- moves or deletes anything. Existing work is found
-- through `.programavimas` files, so a folder the student renamed or moved still belongs to its
-- problem, and folders made by VS Code are found too.

local config = require("programavimas.config")
local i18n = require("programavimas.i18n")
local paths = require("programavimas.paths")
local session = require("programavimas.session")
local t = i18n.t

local M = {}

--- Problem folders sit at most three levels below the root (course/topic/problem).
local MAX_DEPTH = 5
local MAX_MARKERS = 5000

-- ------------------------------------------------------------------ remembered choices

local function state_file() return vim.fs.joinpath(session.dir(), "state.json") end

function M.state() return session.read_json(state_file()) end

---@param key string
---@param value any
function M.remember(key, value)
  local state = M.state()
  state[key] = value
  session.write_json(state_file(), state)
end

---@param course_id string
function M.last_language(course_id)
  local languages = M.state().lastLanguage
  return type(languages) == "table" and languages[course_id] or nil
end

---@param course_id string
---@param language string
function M.remember_language(course_id, language)
  local languages = M.state().lastLanguage
  languages = type(languages) == "table" and languages or {}
  languages[course_id] = language
  M.remember("lastLanguage", languages)
end

-- ------------------------------------------------------------------ the root folder

---@return string?
function M.root()
  local folder = config.options.solutions_dir or M.state().solutionsDir
  if type(folder) ~= "string" or folder == "" then return nil end
  return vim.fs.normalize(folder)
end

---@param path string
local function is_dir(path)
  local stat = vim.uv.fs_stat(path)
  return stat ~= nil and stat.type == "directory"
end

--- Asks where solutions live and remembers the answer. Inside a task.
---@return string?
function M.choose_root()
  local async = require("programavimas.async")
  local cwd = vim.fs.normalize(vim.fn.getcwd())
  local choices = { { label = t("folder.current", { path = vim.fn.fnamemodify(cwd, ":~") }), path = cwd }, { label = t("folder.other") } }
  local choice = async.await(function(done)
    vim.ui.select(choices, {
      prompt = t("folder.pickTitle"),
      format_item = function(item) return item.label end,
    }, done)
  end)
  if not choice then return nil end
  local path = choice.path
  if not path then
    path = async.await(function(done)
      vim.ui.input({ prompt = t("folder.input"), default = cwd .. "/", completion = "dir" }, done)
    end)
    if not path or vim.trim(path) == "" then return nil end
    path = vim.fs.normalize(vim.fn.fnamemodify(vim.trim(path), ":p"))
  end
  path = path:gsub("/+$", "")
  if not is_dir(path) and vim.fn.mkdir(path, "p") == 0 then
    require("programavimas.ui").error(t("folder.notCreated", { path = path }))
    return nil
  end
  M.remember("solutionsDir", path)
  M.index = nil
  return path
end

-- ------------------------------------------------------------------ finding work

--- A file's bytes, or nil when it cannot be read.
---@param path string
---@return string?
function M.read(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end
local read = M.read

---@type table<string, programavimas.Marker|false>  folder → marker (false: none)
local markers = {}

--- The marker of a folder, cached.
---@param folder string
---@return programavimas.Marker?
function M.marker(folder)
  local cached = markers[folder]
  if cached == nil then
    local text = read(vim.fs.joinpath(folder, paths.MARKER_FILE))
    cached = text and paths.parse_marker(text) or false
    markers[folder] = cached
  end
  return cached or nil
end

---@param folder string
function M.forget(folder) markers[folder] = nil end

---@type table<string, string>?  problem key → folder
M.index = nil

--- Markers under the root: at most MAX_DEPTH levels, past dot folders and node_modules.
---@param root string
function M.build_index(root)
  local index, found = {}, 0
  for name, kind in vim.fs.dir(root, {
    depth = MAX_DEPTH,
    skip = function(dir)
      local name = vim.fs.basename(dir)
      return not vim.startswith(name, ".") and name ~= "node_modules"
    end,
  }) do
    if kind == "file" and vim.fs.basename(name) == paths.MARKER_FILE then
      local folder = vim.fs.joinpath(root, vim.fs.dirname(name))
      local marker = M.marker(folder)
      if marker then
        local key = paths.problem_key(marker.server, marker.courseId, marker.problemId)
        -- Two folders for one problem (a copy): the first found wins; neither is touched.
        index[key] = index[key] or folder
      end
      found = found + 1
      if found >= MAX_MARKERS then break end
    end
  end
  return index
end

---@return string?
function M.folder_of(course_id, problem_id)
  local root, server = M.root(), config.origin()
  if not root or not server or not is_dir(root) then return nil end
  M.index = M.index or M.build_index(root)
  local folder = M.index[paths.problem_key(server, course_id, problem_id)]
  if folder and not M.marker(folder) then
    M.index = nil
    return nil
  end
  return folder
end

--- Every known problem folder of the current server.
---@return { folder: string, marker: programavimas.Marker }[]
function M.known()
  local root, server = M.root(), config.origin()
  if not root or not server or not is_dir(root) then return {} end
  M.index = M.index or M.build_index(root)
  local list = {}
  for _, folder in pairs(M.index) do
    local marker = M.marker(folder)
    if marker and marker.server == server then table.insert(list, { folder = folder, marker = marker }) end
  end
  return list
end

---@class programavimas.Solution
---@field folder string
---@field marker programavimas.Marker
---@field main string    The main file run and submit use: the open one, else the marker's
---@field language string

--- The solution a file belongs to: any file in a folder with a `.programavimas` file of the
--- current server, however it was opened. A main file sets the language; any other file (the
--- input file, notes) uses the marker's.
---@param path string
---@return programavimas.Solution?
function M.solution_for(path)
  if path == "" or path:match("^%a[%w+.-]*://") then return nil end
  local folder = vim.fs.dirname(vim.fs.normalize(path))
  local marker = M.marker(folder)
  if not marker or marker.server ~= config.origin() then return nil end
  local language = paths.language_of_file(vim.fs.basename(path)) or marker.language
  return {
    folder = folder,
    marker = marker,
    main = vim.fs.joinpath(folder, paths.solution_file(language)),
    language = language,
  }
end

-- ------------------------------------------------------------------ creating work

---@param path string
local function exists(path) return vim.uv.fs_stat(path) ~= nil end

--- Missing, empty or only whitespace: nothing the student wrote would be lost.
---@param path string
function M.is_blank(path)
  local text = read(path)
  return text == nil or vim.trim(text) == ""
end

--- Creates a file only when nothing is there: local files are the student's drafts.
---@param path string
---@param content string
local function write_if_missing(path, content)
  if exists(path) then return false end
  local file = assert(io.open(path, "wb"))
  file:write(content)
  file:close()
  return true
end

--- Fills a missing or blank file (never one with anything written in it).
---@param path string
---@param content string
local function fill_if_blank(path, content)
  if not M.is_blank(path) then return false end
  local file = assert(io.open(path, "wb"))
  file:write(content)
  file:close()
  return true
end

---@param root string
---@param layout programavimas.Layout
---@param problem_id string
local function new_folder(root, layout, problem_id)
  local segments = paths.problem_segments(layout)
  local name = table.remove(segments)
  local parent = vim.fs.joinpath(root, unpack(segments))
  -- A taken name holds someone else's files or another problem: never write into it.
  for _, candidate in ipairs({ name, paths.with_id_suffix(name, problem_id), name .. "-" .. problem_id }) do
    local folder = vim.fs.joinpath(parent, candidate)
    if not exists(folder) then
      vim.fn.mkdir(folder, "p")
      return folder
    end
  end
  error("no free folder name")
end

---@class programavimas.Prepared
---@field solution programavimas.Solution
---@field created boolean
---@field started "draft"|"submission"|nil  Where a new main file's code came from

--- Finds the problem's folder or creates it with its files: the main file, the custom input
--- file (sample 1) and the marker. Existing files are never touched; a missing main file of
--- the chosen language is added beside the others. A new or blank main file starts from the
--- student's newest server draft or submission, else the starter code. Inside a task.
---@param detail table  The problem detail
---@param layout programavimas.Layout
---@param root string
---@param me table?  `/me`, for the preferred language
---@return programavimas.Prepared?
function M.prepare(detail, layout, root, me)
  local api = require("programavimas.api")
  local async = require("programavimas.async")
  local server = config.origin()
  local allowed = vim.tbl_map(function(language) return language.code end, paths.editable_languages(detail.languages or {}))
  if not server or #allowed == 0 then return nil end
  local existing = M.folder_of(detail.course.id, detail.id)
  local existing_marker = existing and M.marker(existing) or nil
  local kept = existing_marker and vim.tbl_contains(allowed, existing_marker.language) and existing_marker.language or nil

  local start, drafts
  local blank = not kept or not existing or M.is_blank(vim.fs.joinpath(existing, paths.solution_file(kept)))
  if blank then
    local latest
    drafts, latest = unpack(async.all({
      function() return (api.drafts(detail.course.id, detail.id) or {}).items end,
      function()
        local submission = api.latest_submission(detail.course.id, detail.id)
        return submission and {
          language = submission.language.code,
          source = submission.source,
          submittedAt = submission.submittedAt,
        } or nil
      end,
    }))
    start = paths.start_content({ drafts = drafts or {}, latest = latest }, allowed, kept)
  end

  local language = kept
    or (start and start.language)
    or paths.choose_language(allowed, M.last_language(detail.course.id), me and me.preferredLanguage)
  if not language then return nil end

  local folder = existing or new_folder(root, layout, detail.id)
  local marker = {
    v = 1,
    server = server,
    courseId = detail.course.id,
    topicId = detail.topic and detail.topic.id or nil,
    problemId = detail.id,
    language = language,
  }
  local main = vim.fs.joinpath(folder, paths.solution_file(language))
  local started
  if start and start.language == language and fill_if_blank(main, start.source) then
    started = start.origin
    local draft
    for _, item in ipairs(drafts or {}) do
      if item.language == language then draft = item end
    end
    require("programavimas.drafts").started({ folder = folder, marker = marker, main = main, language = language }, draft, start.source)
  else
    write_if_missing(main, (detail.starterCode or {})[language] or "")
  end
  if not existing then
    write_if_missing(vim.fs.joinpath(folder, paths.custom_input_name(detail.io)), ((detail.samples or {})[1] or {}).input or "")
    write_if_missing(vim.fs.joinpath(folder, paths.MARKER_FILE), paths.encode_marker(marker))
    markers[folder] = nil
    M.index = nil
    vim.api.nvim_exec_autocmds("User", { pattern = "ProgramavimasFolder", data = { folder = folder } })
  end
  M.remember_language(detail.course.id, language)
  return {
    solution = { folder = folder, marker = existing_marker or marker, main = main, language = language },
    created = not existing,
    started = started,
  }
end

--- Switches a problem to another allowed language, adding its main file when missing.
---@param solution programavimas.Solution
---@param detail table
---@param language string
---@return programavimas.Solution
function M.switch_language(solution, detail, language)
  local main = vim.fs.joinpath(solution.folder, paths.solution_file(language))
  write_if_missing(main, (detail.starterCode or {})[language] or "")
  local marker = vim.deepcopy(solution.marker)
  marker.language = language
  -- The marker is our own file; only its language changes.
  local file = assert(io.open(vim.fs.joinpath(solution.folder, paths.MARKER_FILE), "wb"))
  file:write(paths.encode_marker(marker))
  file:close()
  markers[solution.folder] = marker
  M.remember_language(detail.course.id, language)
  return { folder = solution.folder, marker = marker, main = main, language = language }
end

return M
