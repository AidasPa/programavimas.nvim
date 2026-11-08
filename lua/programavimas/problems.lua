-- Opening problems: the detail from the API, the solution folder (found or created), the main
-- file in the editor and the statement beside it. Also the language switch and "create course
-- folders".

local account = require("programavimas.account")
local api = require("programavimas.api")
local async = require("programavimas.async")
local i18n = require("programavimas.i18n")
local paths = require("programavimas.paths")
local solutions = require("programavimas.solutions")
local ui = require("programavimas.ui")
local t = i18n.t

local M = {}

---@type table<string, table>  "course|problem" → the problem detail last loaded
M.details = {}

local function key(course_id, problem_id) return course_id .. "|" .. problem_id end

--- The problem detail, loaded (inside a task).
---@return table? detail, programavimas.ApiError? err
function M.detail(course_id, problem_id, force)
  local cached = M.details[key(course_id, problem_id)]
  if cached and not force then return cached, nil end
  local detail, err = api.problem(course_id, problem_id)
  if detail then M.details[key(course_id, problem_id)] = detail end
  return detail, err
end

--- The solutions folder, asked for once.
local function root()
  return solutions.root() or solutions.choose_root()
end

--- Opens a problem's main file with its statement beside it.
function M.open(course_id, problem_id)
  async.run(function()
    if not account.signed_in() then return ui.notify(t("auth.notSignedIn")) end
    local me = account.load()
    local detail, err = M.detail(course_id, problem_id, true)
    if not detail then return ui.error(err and ui.api_message(err) or t("open.loadFailed")) end
    if #paths.editable_languages(detail.languages or {}) == 0 then
      ui.warn(t("open.noLanguage"))
      return require("programavimas.statement").show(detail, true)
    end
    local located = require("programavimas.courses").locate(course_id, problem_id)
    if not located then return ui.error(t("open.loadFailed")) end
    local folder = root()
    if not folder then return end
    local prepared = solutions.prepare(detail, located.layout, folder, me)
    if not prepared then return ui.warn(t("open.noLanguage")) end
    -- The editor goes to a window that is not one of ours (sidebar, statement, results).
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
      local name = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win))
      if not vim.startswith(name, "programavimas://") and vim.api.nvim_win_get_config(win).relative == "" then
        vim.api.nvim_set_current_win(win)
        break
      end
    end
    if vim.startswith(vim.api.nvim_buf_get_name(0), "programavimas://") then vim.cmd("rightbelow vsplit") end
    vim.cmd.edit(vim.fn.fnameescape(prepared.solution.main))
    if prepared.started then
      ui.notify(t("open.started", { source = t("open.source." .. prepared.started) }))
    end
    require("programavimas.statement").show(detail)
  end)
end

--- Loads a problem again and updates its statement (and the status line).
function M.reload(course_id, problem_id)
  async.run(function()
    local detail, err = M.detail(course_id, problem_id, true)
    if not detail then return ui.error(ui.api_message(err)) end
    require("programavimas.statement").update(detail)
    require("programavimas.courses").update_status(course_id, problem_id, detail.status)
    vim.cmd.redrawstatus()
  end)
end

--- The solution of the current buffer, or nil after saying how to get one.
---@return programavimas.Solution?
function M.current()
  local solution = solutions.solution_for(vim.api.nvim_buf_get_name(0))
  if not solution then ui.notify(t("open.notSolution"), vim.log.levels.WARN) end
  return solution
end

--- Switches the current solution to another language the problem allows.
function M.switch_language()
  local solution = M.current()
  if not solution then return end
  async.run(function()
    local detail, err = M.detail(solution.marker.courseId, solution.marker.problemId)
    if not detail then return ui.error(ui.api_message(err)) end
    local languages = paths.editable_languages(detail.languages or {})
    local choice = async.await(function(done)
      vim.ui.select(languages, {
        prompt = t("open.language"),
        format_item = function(language)
          return language.name .. (language.code == solution.language and "  ✓" or "")
        end,
      }, done)
    end)
    if not choice or choice.code == solution.language then return end
    local switched = solutions.switch_language(solution, detail, choice.code)
    vim.cmd.edit(vim.fn.fnameescape(switched.main))
  end)
end

--- Creates the folders of every open programming problem of a course.
---@param course table
function M.prepare_course(course)
  async.run(function()
    local folder = root()
    if not folder then return end
    local me = account.load()
    local created, existing = 0, 0
    for _, entry in ipairs(require("programavimas.courses").locate_all(course)) do
      if entry.problem.type == "programming" and entry.problem.status.kind ~= "locked" then
        local detail = M.detail(course.id, entry.problem.id)
        local prepared = detail and solutions.prepare(detail, entry.layout, folder, me)
        if prepared and prepared.created then
          created = created + 1
        elseif prepared then
          existing = existing + 1
        end
      end
    end
    ui.notify(t("course.prepared", { created = created, existing = existing }))
  end)
end

return M
