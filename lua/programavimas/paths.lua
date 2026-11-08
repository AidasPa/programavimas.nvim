-- The solutions folder's layout, pure. The same as the VS Code extension's
-- (apps/vscode/src/workspace/paths.ts and languages.ts), so a student can switch editors and
-- keep their folders:
--
--   <root>/<course>/<NN>-<topic>/<NN>-<problem>/
--     main.cpp | main.py | main.cs   the solution (another when the student switches language)
--     input.txt | duom.txt           custom input, prefilled with sample 1
--     .programavimas                 ids and the language only
--
-- Paths are only built for new folders: existing work is found by its `.programavimas` file,
-- so renamed or moved folders keep their files.

local M = {}

M.MARKER_FILE = ".programavimas"
local MAX_SLUG = 48

M.LANGUAGES = {
  cpp = { file = "main.cpp", compiler = "g++", filetype = "cpp" },
  python = { file = "main.py", compiler = "python", filetype = "python" },
  csharp = { file = "main.cs", compiler = "csc", filetype = "cs" },
}

---@param code any
---@return boolean
function M.is_editor_language(code)
  return type(code) == "string" and M.LANGUAGES[code] ~= nil
end

---@param language string
function M.solution_file(language)
  return M.LANGUAGES[language].file
end

---@param name string
---@return string?
function M.language_of_file(name)
  for code, language in pairs(M.LANGUAGES) do
    if language.file == name then return code end
  end
  return nil
end

--- A problem's languages Neovim can edit, in the server's order (C++ first).
---@param languages { code: string, name: string }[]
function M.editable_languages(languages)
  return vim.tbl_filter(function(language) return M.is_editor_language(language.code) end, languages)
end

local RESERVED = { con = true, prn = true, aux = true, nul = true }
for digit = 1, 9 do
  RESERVED["com" .. digit] = true
  RESERVED["lpt" .. digit] = true
end

--- Names Windows cannot create, with or without an extension.
---@param name string
local function reserved(name)
  return RESERVED[(name:lower():match("^([^.]*)"))] == true
end

local TRANSLIT = require("programavimas.slug_table")

--- The code point of one UTF-8 character.
---@param char string
local function codepoint(char)
  local b1, b2, b3, b4 = char:byte(1, 4)
  if #char == 2 then return (b1 % 0x20) * 0x40 + b2 % 0x40 end
  if #char == 3 then return ((b1 % 0x10) * 0x40 + b2 % 0x40) * 0x40 + b3 % 0x40 end
  return (((b1 % 0x08) * 0x40 + b2 % 0x40) * 0x40 + b3 % 0x40) * 0x40 + (b4 or 0) % 0x40
end

--- Combining marks, which NFD separates from their letters and `slug` drops.
---@param code integer
local function combining(code)
  return (code >= 0x300 and code <= 0x36F)
    or (code >= 0x1AB0 and code <= 0x1AFF)
    or (code >= 0x1DC0 and code <= 0x1DFF)
    or (code >= 0x20D0 and code <= 0x20FF)
    or (code >= 0xFE20 and code <= 0xFE2F)
end

--- "Dvejetainė paieška" → "dvejetaine-paieska": no diacritics, lower case, dashes.
---@param title string
function M.slug(title)
  local out = {}
  for char in title:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if #char == 1 then
      table.insert(out, char:lower())
    elseif TRANSLIT[char] then
      table.insert(out, TRANSLIT[char])
    elseif not combining(codepoint(char)) then
      table.insert(out, "-")
    end
  end
  local plain = table.concat(out):gsub("[^a-z0-9]+", "-"):gsub("^%-+", ""):gsub("%-+$", "")
  local cut = plain:sub(1, MAX_SLUG):gsub("%-+$", "")
  if cut == "" then cut = "be-pavadinimo" end
  return reserved(cut) and cut .. "-1" or cut
end

--- "03-dvejetaine-paieska": two-digit positions (three past 99) keep course order.
---@param position number
---@param title string
function M.positioned(position, title)
  return ("%02d-%s"):format(math.max(1, math.floor(position)), M.slug(title))
end

---@class programavimas.Layout
---@field course { title: string }
---@field topic { position: integer, title: string }?  nil for course-wide problems
---@field problem { position: integer, title: string }

--- Folder names from the root down to a new problem folder.
---@param layout programavimas.Layout
---@return string[]
function M.problem_segments(layout)
  local segments = { M.slug(layout.course.title) }
  if layout.topic then table.insert(segments, M.positioned(layout.topic.position, layout.topic.title)) end
  table.insert(segments, M.positioned(layout.problem.position, layout.problem.title))
  return segments
end

--- A taken folder name (someone else's files, or another problem) gets a piece of the id.
---@param segment string
---@param id string
function M.with_id_suffix(segment, id)
  local suffix = id:gsub("%-", ""):sub(-6):lower()
  local head = segment:sub(1, MAX_SLUG + 4 - #suffix - 1):gsub("%-+$", "")
  return head .. "-" .. suffix
end

--- A file name that is safe to create on every OS and is not one of ours. The API sends file
--- I/O names as the problem stores them (legacy names unchanged), so this is the decision.
---@param name string
function M.is_safe_file_name(name)
  if #name > 64 or not name:match("^[A-Za-z0-9][A-Za-z0-9._-]*$") then return false end
  if name:find("..", 1, true) or reserved(name) or name == M.MARKER_FILE then return false end
  return M.language_of_file(name) == nil
end

--- The file a custom run reads: the problem's own input file for file I/O when its name is
--- safe here, else input.txt (the statement still shows the original name).
---@param io { kind: "stdio"|"files", input?: string }
function M.custom_input_name(io)
  return io.kind == "files" and M.is_safe_file_name(io.input) and io.input or "input.txt"
end

--- The language to start with: the last one used in this course, else the account's
--- preference, else the first allowed (C++ first, as the server orders them).
---@param allowed string[]
---@param last_used string?
---@param preferred string?
---@return string?
function M.choose_language(allowed, last_used, preferred)
  for _, candidate in ipairs({ last_used or false, preferred or false }) do
    if M.is_editor_language(candidate) and vim.tbl_contains(allowed, candidate) then return candidate end
  end
  return allowed[1]
end

-- ------------------------------------------------------------------ the marker

local UUID = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

---@class programavimas.Marker
---@field v 1
---@field server string     The server origin the ids belong to
---@field courseId string
---@field topicId string?
---@field problemId string
---@field language string   The solution file the problem's commands use

---@param text string
---@return programavimas.Marker?
function M.parse_marker(text)
  local ok, value = pcall(vim.json.decode, text, { luanil = { object = true, array = true } })
  if not ok or type(value) ~= "table" or value.v ~= 1 then return nil end
  if type(value.server) ~= "string" or #value.server == 0 or #value.server > 256 then return nil end
  for _, key in ipairs({ "courseId", "problemId" }) do
    if type(value[key]) ~= "string" or not value[key]:match(UUID) then return nil end
  end
  if value.topicId ~= nil and (type(value.topicId) ~= "string" or not value.topicId:match(UUID)) then
    return nil
  end
  if not M.is_editor_language(value.language) then return nil end
  return {
    v = 1,
    server = value.server,
    courseId = value.courseId,
    topicId = value.topicId,
    problemId = value.problemId,
    language = value.language,
  }
end

---@param value string
local function json_string(value)
  return '"'
    .. value:gsub('[%c"\\]', function(char)
      if char == '"' or char == "\\" then return "\\" .. char end
      return ("\\u%04x"):format(char:byte())
    end)
    .. '"'
end

--- The marker as the VS Code extension writes it (`JSON.stringify(marker, null, 2)`).
---@param marker programavimas.Marker
function M.encode_marker(marker)
  return table.concat({
    "{",
    '  "v": 1,',
    '  "server": ' .. json_string(marker.server) .. ",",
    '  "courseId": ' .. json_string(marker.courseId) .. ",",
    '  "topicId": ' .. (marker.topicId and json_string(marker.topicId) or "null") .. ",",
    '  "problemId": ' .. json_string(marker.problemId) .. ",",
    '  "language": ' .. json_string(marker.language),
    "}",
    "",
  }, "\n")
end

--- The key a problem's folder is indexed by.
function M.problem_key(server, course_id, problem_id)
  return server .. "|" .. course_id .. "|" .. problem_id
end

-- ------------------------------------------------------------------ the first content

---@class programavimas.StartCandidates
---@field drafts { language: string, code: string, savedAt: string }[]  The server drafts
---@field latest { language: string, source: string, submittedAt: string }?  Newest submission

--- What a new (or still blank) main file starts from: the newest of the student's server
--- draft and newest submission (work done in the browser or on another computer), else the
--- starter code. With no language chosen yet, the newest one decides it among `allowed`.
---@param candidates programavimas.StartCandidates
---@param allowed string[]
---@param language string?  The language already chosen (the marker's), if any
---@return { language: string, source: string, origin: "draft"|"submission" }?
function M.start_content(candidates, allowed, language)
  local time = require("programavimas.time")
  local best
  local function consider(lang, source, at, origin)
    if not vim.tbl_contains(allowed, lang) or (language and lang ~= language) then return end
    if vim.trim(source) == "" then return end
    local epoch = time.parse(at) or 0
    if not best or epoch > best.epoch then
      best = { language = lang, source = source, origin = origin, epoch = epoch }
    end
  end
  for _, draft in ipairs(candidates.drafts or {}) do
    consider(draft.language, draft.code, draft.savedAt, "draft")
  end
  local latest = candidates.latest
  if latest then consider(latest.language, latest.source, latest.submittedAt, "submission") end
  if not best then return nil end
  return { language = best.language, source = best.source, origin = best.origin }
end

return M
