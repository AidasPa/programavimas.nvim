-- The plugin's tests: `nvim --headless --clean -l test/run.lua` from apps/nvim (or `bun run
-- test:nvim`). Every `test/*_spec.lua` runs with `describe`, `it` and `eq`; no other plugin.

local root = vim.fs.dirname(vim.fs.dirname(vim.fs.normalize(debug.getinfo(1, "S").source:sub(2))))
vim.opt.runtimepath:prepend(root)
-- Strings in English, whatever this computer uses (dates are always Lithuanian time).
require("programavimas.config").setup({ language = "en" })

local passed, failed, names = 0, 0, {}

function _G.describe(name, fn)
  table.insert(names, name)
  fn()
  table.remove(names)
end

function _G.it(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  local full = table.concat(names, " › ") .. " › " .. name
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    io.stderr:write("✗ " .. full .. "\n" .. tostring(err) .. "\n\n")
  end
end

function _G.eq(expected, actual, message)
  if not vim.deep_equal(expected, actual) then
    error(("%sexpected %s, got %s"):format(message and message .. ": " or "", vim.inspect(expected), vim.inspect(actual)), 2)
  end
end

--- A substring check that shows the whole text when it fails.
function _G.contains(text, part)
  if not text:find(part, 1, true) then error(("%q not in:\n%s"):format(part, text), 2) end
end

local files = vim.fn.glob(root .. "/test/*_spec.lua", false, true)
table.sort(files)
for _, file in ipairs(files) do
  local ok, err = xpcall(dofile, debug.traceback, file)
  if not ok then
    failed = failed + 1
    io.stderr:write("✗ " .. file .. "\n" .. tostring(err) .. "\n\n")
  end
end
io.stdout:write(("%d passed, %d failed\n"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
