-- Coroutines over callbacks: `run(fn)` starts a task, `await(start)` inside it waits for a
-- callback-style operation and resumes on the main loop, where every Neovim API is allowed.

local M = {}

---@type table<thread, fun(...)>
local steps = setmetatable({}, { __mode = "k" })

---@param fn fun(...)
---@param on_error? fun(err: any)  Defaults to an error notification
function M.run(fn, on_error)
  local co = coroutine.create(fn)
  local function step(...)
    local ok, err = coroutine.resume(co, ...)
    if not ok then
      steps[co] = nil
      local report = on_error
        or function(e)
          vim.notify(
            "Programavimas: " .. tostring(e) .. "\n" .. debug.traceback(co),
            vim.log.levels.ERROR
          )
        end
      vim.schedule(function() report(err) end)
    elseif coroutine.status(co) == "dead" then
      steps[co] = nil
    end
  end
  steps[co] = step
  step()
end

--- Waits for `start(done)` to call `done(...)` and returns its arguments. Only inside `run`.
---@param start fun(done: fun(...))
---@return ...
function M.await(start)
  local co = coroutine.running()
  local step = co and steps[co]
  assert(step, "programavimas: await outside a task")
  local called = false
  start(function(...)
    if called then return end
    called = true
    local args = vim.F.pack_len(...)
    vim.schedule(function() step(vim.F.unpack_len(args)) end)
  end)
  return coroutine.yield()
end

---@param ms integer
function M.sleep(ms)
  M.await(function(done) vim.defer_fn(done, ms) end)
end

--- Runs several tasks at once and returns their first results in order; a task that fails
--- gives nil (and is reported), so the caller always resumes.
---@param fns (fun(): any)[]
---@return any[]
function M.all(fns)
  if #fns == 0 then return {} end
  return M.await(function(done)
    local results, left = {}, #fns
    for index, fn in ipairs(fns) do
      M.run(function()
        local ok, value = pcall(fn)
        if ok then
          results[index] = value
        else
          vim.schedule(function() vim.notify("Programavimas: " .. tostring(value), vim.log.levels.ERROR) end)
        end
        left = left - 1
        if left == 0 then done(results) end
      end)
    end
  end)
end

return M
