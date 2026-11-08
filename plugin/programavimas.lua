-- Loaded at startup: the command, the <Plug> mappings and the solution-buffer detection only;
-- everything else loads on first use.

if vim.g.loaded_programavimas then return end
vim.g.loaded_programavimas = true

if vim.fn.has("nvim-0.10") == 0 then
  vim.notify("Programavimas needs Neovim 0.10 or later.", vim.log.levels.ERROR)
  return
end

vim.api.nvim_create_user_command("Programavimas", function(opts)
  require("programavimas").dispatch(opts.fargs)
end, {
  nargs = "*",
  desc = "Programavimas: courses, statements, runs and submissions",
  complete = function(arg, line) return require("programavimas").complete(arg, line) end,
})

for name, command in pairs({
  run = "run",
  custom = "custom",
  submit = "submit",
  statement = "statement",
  results = "results",
  courses = "courses",
  open = "open",
  language = "language",
  sync = "sync",
}) do
  vim.keymap.set("n", "<Plug>(programavimas-" .. name .. ")", function()
    require("programavimas").dispatch({ command })
  end, { desc = "Programavimas: " .. name })
end

local group = vim.api.nvim_create_augroup("programavimas", { clear = true })

vim.api.nvim_create_autocmd("ColorScheme", {
  group = group,
  callback = function() require("programavimas.ui").highlights() end,
})
require("programavimas.ui").highlights()

-- A file in a problem folder (a `.programavimas` file beside it) becomes a solution buffer.
-- The check is one stat per new folder, so other files cost nothing noticeable.
local checked = {}
vim.api.nvim_create_autocmd({ "BufReadPost", "BufNewFile" }, {
  group = group,
  callback = function(event)
    local name = vim.api.nvim_buf_get_name(event.buf)
    if name == "" or vim.bo[event.buf].buftype ~= "" then return end
    local folder = vim.fs.dirname(name)
    if checked[folder] == nil then
      checked[folder] = vim.uv.fs_stat(vim.fs.joinpath(folder, ".programavimas")) ~= nil
    end
    if checked[folder] then require("programavimas").attach(event.buf) end
  end,
})
-- A marker written by this or another editor makes its folder a problem folder at once.
vim.api.nvim_create_autocmd("User", {
  group = group,
  pattern = "ProgramavimasFolder",
  callback = function(event) checked[event.data and event.data.folder or ""] = nil end,
})
