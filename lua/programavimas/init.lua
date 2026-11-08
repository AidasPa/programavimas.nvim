-- Programavimas for Neovim: courses, statements, runs and submissions of programavimas.xyz in
-- the editor. Code never runs on this computer; runs and submissions go to the judge.
--
--   require("programavimas").setup({ ... })   -- optional; see :help programavimas-config
--   :Programavimas {login|logout|account|courses|open|statement|run|custom|submit|results|
--                   submissions|language|sync|browser|folder}

local M = {}

---@param opts? table
function M.setup(opts)
  require("programavimas.config").setup(opts)
  require("programavimas.ui").highlights()
end

--- What each subcommand does.
---@type table<string, fun(args: string[])>
M.commands = {
  login = function(args) require("programavimas.account").login(args[1] == "device" and "device" or args[1] == "browser" and "browser" or nil) end,
  logout = function() require("programavimas.account").logout() end,
  account = function() require("programavimas.account").menu() end,
  courses = function() require("programavimas.courses").toggle() end,
  open = function() require("programavimas.courses").pick() end,
  statement = function() M.statement() end,
  run = function() require("programavimas.judge").start("samples") end,
  custom = function() require("programavimas.judge").start("custom") end,
  submit = function() require("programavimas.judge").start("submit") end,
  results = function() require("programavimas.results").toggle() end,
  submissions = function() require("programavimas.judge").pick_submission() end,
  language = function() require("programavimas.problems").switch_language() end,
  sync = function() require("programavimas.drafts").sync_now() end,
  browser = function() M.browser() end,
  folder = function()
    require("programavimas.async").run(function()
      local path = require("programavimas.solutions").choose_root()
      if path then
        require("programavimas.ui").notify(require("programavimas.i18n").t("folder.changed", { path = vim.fn.fnamemodify(path, ":~") }))
      end
    end)
  end,
}

--- The statement of the current solution's problem.
function M.statement()
  local solution = require("programavimas.problems").current()
  if not solution then return end
  require("programavimas.async").run(function()
    local problems = require("programavimas.problems")
    local detail, err = problems.detail(solution.marker.courseId, solution.marker.problemId, true)
    if not detail then return require("programavimas.ui").error(require("programavimas.ui").api_message(err)) end
    require("programavimas.statement").show(detail)
  end)
end

--- The current solution's problem page in the browser.
function M.browser()
  local solution = require("programavimas.problems").current()
  if not solution then return end
  vim.ui.open(require("programavimas.api").problem_page(solution.marker.courseId, solution.marker.problemId))
end

---@param line string
function M.complete(_, line)
  local words = vim.split(line, "%s+", { trimempty = true })
  if #words <= 1 or (#words == 2 and not line:match("%s$")) then
    local names = vim.tbl_keys(M.commands)
    table.sort(names)
    local prefix = words[2] or ""
    return vim.tbl_filter(function(name) return vim.startswith(name, prefix) end, names)
  end
  if words[2] == "login" then return { "browser", "device" } end
  return {}
end

---@param args string[]
function M.dispatch(args)
  local name = args[1] or "courses"
  local command = M.commands[name]
  if not command then
    return require("programavimas.ui").error("Unknown command: " .. name .. " (:Programavimas <Tab>)")
  end
  command(vim.list_slice(args, 2))
end

--- For statusline plugins: the current solution's problem, judging step and attempts.
function M.statusline()
  return require("programavimas.judge").statusline()
end

-- ------------------------------------------------------------------ solution buffers

local KEYMAPS = {
  run = { "run", "Run samples" },
  custom = { "custom", "Run with custom input" },
  submit = { "submit", "Submit" },
  statement = { "statement", "Show statement" },
  results = { "results", "Show or hide results" },
  language = { "language", "Switch language" },
}

--- Called for every file buffer: a file in a problem folder gets the keys and the status.
---@param buf integer
function M.attach(buf)
  if vim.b[buf].programavimas_attached ~= nil then return end
  local name = vim.api.nvim_buf_get_name(buf)
  local solution = require("programavimas.solutions").solution_for(name)
  vim.b[buf].programavimas_attached = solution ~= nil
  if not solution then return end
  local keymaps = require("programavimas.config").options.keymaps
  if keymaps then
    for option, spec in pairs(KEYMAPS) do
      local lhs = keymaps[option]
      if lhs then
        vim.keymap.set("n", lhs, function() M.commands[spec[1]]({}) end, {
          buffer = buf,
          silent = true,
          desc = "Programavimas: " .. spec[2],
        })
      end
    end
  end
  -- Saves go to the server's draft; opening, entering and coming back compare with it.
  require("programavimas.drafts").attach(buf)
  -- The problem's title and attempts for the status line, without blocking the editor.
  local problems = require("programavimas.problems")
  if not problems.details[solution.marker.courseId .. "|" .. solution.marker.problemId]
    and require("programavimas.account").signed_in()
  then
    require("programavimas.async").run(function()
      problems.detail(solution.marker.courseId, solution.marker.problemId)
      vim.cmd.redrawstatus()
    end, function() end)
  end
end

return M
