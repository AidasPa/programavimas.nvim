-- :checkhealth programavimas

local M = {}

function M.check()
  local health = vim.health
  local config = require("programavimas.config")

  health.start("Neovim and tools")
  if vim.fn.has("nvim-0.10") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.10 or later is needed")
  end
  if vim.fn.executable("curl") == 1 then
    local version = vim.system({ "curl", "--version" }, { text = true }):wait()
    health.ok((vim.split(version.stdout or "curl", "\n")[1]))
  else
    health.error("curl was not found", "Install curl: the plugin talks to the server with it")
  end
  -- The statement is drawn from Markdown with the parsers Neovim comes with.
  local missing = {}
  for _, language in ipairs({ "markdown", "markdown_inline" }) do
    local ok, parser = pcall(vim.treesitter.get_string_parser, "", language)
    if not ok or not parser then table.insert(missing, language) end
  end
  if #missing == 0 then
    health.ok("Tree-sitter parsers markdown and markdown_inline, for statements")
  elseif config.options.statement.render == "markdown" then
    health.info("No Tree-sitter parser " .. table.concat(missing, ", ") .. " (statements are Markdown buffers here)")
  else
    health.warn("No Tree-sitter parser " .. table.concat(missing, ", ") .. ": statements show as plain Markdown", {
      "They come with Neovim: reinstall it, or :TSInstall markdown markdown_inline with nvim-treesitter",
    })
  end

  health.start("Server and account")
  local origin = config.origin()
  if not origin then
    health.error(("The server setting %q is not usable"):format(tostring(config.options.server)), {
      "Use https://…, or http://localhost:… for a development server",
    })
    return
  end
  health.ok("Server: " .. origin)
  local session = require("programavimas.session").get(origin)
  if session then
    health.ok("Signed in as " .. session.accountName)
  else
    health.warn("Not signed in", "Run :Programavimas login (or :Programavimas login device over SSH)")
  end
  local probe = vim.system({
    "curl", "--silent", "--max-time", "10", "--output", vim.fn.has("win32") == 1 and "NUL" or "/dev/null",
    "--write-out", "%{http_code}", origin .. "/.well-known/oauth-authorization-server",
  }, { text = true }):wait()
  if probe.code == 0 and vim.trim(probe.stdout or "") == "200" then
    health.ok("The server answers")
  else
    health.warn("The server did not answer (" .. vim.trim(probe.stdout or "") .. ")", "Check the connection")
  end

  health.start("Solutions")
  local root = require("programavimas.solutions").root()
  if root then
    local stat = vim.uv.fs_stat(root)
    if stat and stat.type == "directory" then
      health.ok("Solutions folder: " .. root)
    else
      health.warn("Solutions folder " .. root .. " does not exist yet", "It is created when a problem opens")
    end
  else
    health.info("No solutions folder yet: you are asked when you open the first problem")
  end
  local keymaps = config.options.keymaps
  health.info(keymaps and ("Keys in solution files: run %s, custom %s, submit %s"):format(
    tostring(keymaps.run), tostring(keymaps.custom), tostring(keymaps.submit)
  ) or "No keys in solution files (keymaps = false)")
end

return M
