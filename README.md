# Programavimas for Neovim

Your [programavimas.xyz](https://beta.programavimas.xyz) courses in Neovim: topics and problems
in a sidebar, the statement beside your code, your solutions as ordinary files, and **Run
samples**, **Run with custom input** and **Submit** on the same judge as the browser. Your
code never runs on your computer, and you only ever see your own results.

It's the twin of the [VS Code extension](https://beta.programavimas.xyz/docs/en/students/vs-code/):
the same account, the same folders, the same results.

- Neovim 0.10 or later, and `curl` (built into macOS, Windows 10+ and most Linux systems)
- Nothing else: no Node, no Python, no plugins it depends on

## Install

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "AidasPa/programavimas.nvim",
  opts = {},
}
```

With Neovim's built-in package manager (0.12+): `vim.pack.add({ "https://github.com/AidasPa/programavimas.nvim" })`
and then `require("programavimas").setup()`. Any other plugin manager works the same way.

Then `:Programavimas login`. Your browser opens the sign-in page; allow access and come back.
Working over SSH, or without a browser? `:Programavimas login device` shows a code to type at
the address it gives, on any device.

## Use

| Command | What it does |
| --- | --- |
| `:Programavimas` or `:Programavimas courses` | Show or hide your courses |
| `:Programavimas open` | Search every problem of your courses and open one |
| `:Programavimas statement` | The statement of the problem you're on |
| `:Programavimas run` | Run the samples (not graded, as often as you like) |
| `:Programavimas custom` | Run with your own input: the problem's input file (`input.txt`, or `duom.txt` and such) |
| `:Programavimas submit` | Submit: graded, uses one of today's attempts |
| `:Programavimas results` | Show or hide the tests and results |
| `:Programavimas submissions` | Your recent submissions and their results |
| `:Programavimas language` | Switch the problem to another language it allows |
| `:Programavimas browser` | Open the problem in the browser |
| `:Programavimas folder` | Change where solutions are kept |
| `:Programavimas account` | Who you're signed in as; sign out |
| `:Programavimas logout` | Sign out (your files stay) |

In a solution file: `<localleader>r` runs the samples, `<localleader>i` runs with your input,
`<localleader>s` submits, `<localleader>p` shows the statement, `<localleader>t` the results and
`<localleader>l` switches the language. In the sidebar, the statement and the results, `?`
lists their keys.

Opening a problem the first time asks where solutions should live, then makes a folder for
it there:

```text
<solutions>/
  algoritmai-11/                       course
    01-paieska-ir-rikiavimas/          topic, in course order
      01-dvejetaine-paieska/           problem
        main.cpp                       your solution (main.py, main.cs)
        input.txt                      your own input, starts as sample 1
        .programavimas                 which problem this is
```

A new solution starts from your newest code on the server (a draft the browser saved, or your
latest submission), so work done elsewhere comes along. Nothing you wrote is ever
overwritten, moved or deleted. The VS Code extension uses the same folders: point both at one
folder and switch editors whenever you like.

Compiler messages show as diagnostics in your code. The judging step and your attempts are in
`require("programavimas").statusline()`, for your status line:

```lua
-- lualine
sections = { lualine_x = { require("programavimas").statusline } }
-- or plain
vim.o.statusline = "%f %= %{v:lua.require'programavimas'.statusline()} "
```

`:checkhealth programavimas` checks the setup. `:help programavimas` has everything else.

## Settings

```lua
require("programavimas").setup({
  server = "https://beta.programavimas.xyz", -- https, or http for localhost only
  solutions_dir = nil,      -- nil: asked the first time you open a problem
  language = "account",     -- "account" (your account's language), "lt" or "en"
  save_before_run = true,   -- write a changed solution before running or submitting
  keymaps = {               -- in solution files; false turns one (or all) off
    run = "<localleader>r",
    custom = "<localleader>i",
    submit = "<localleader>s",
    statement = "<localleader>p",
    results = "<localleader>t",
    language = "<localleader>l",
  },
  courses = { width = 42, position = "left" },
  results = { height = 14 },
  icons = {},               -- e.g. { complete = "", accepted = "" } with a Nerd Font
})
```

Colours follow your colour scheme: the `Programavimas*` highlight groups link to the
diagnostic groups (`DiagnosticOk`, `DiagnosticError`, …) and can be overridden.

## Privacy

Sign-in is standard OAuth 2.0 with PKCE. The tokens are kept in
`stdpath("data")/programavimas/sessions.json`, readable only by you, and go only to the
server they came from; `curl` gets them on its standard input, never on a command line.
Signing out ends the session on the server too.

## Development

This is a published copy of `apps/nvim` in the programavimas.xyz repository, updated after
every change there. In that repository (from `v2/`):

- `nvim --headless --clean -l apps/nvim/test/run.lua` runs the Lua specs (`test/*_spec.lua`);
- `bun test apps/nvim` also runs the end-to-end test: a headless Neovim against a mock of the
  server (`test/mock-server.ts`, bodies checked with `@programavimas/api-contract`);
- `bun apps/nvim/test/preview-server.ts 4319` serves that mock for trying the plugin by hand
  (`setup({ server = "http://127.0.0.1:4319" })`, and replace `vim.ui.open` with
  `curl -sSL` so signing in completes without a browser).

How it fits the server (docs/public-api.md in the repository):

| Module | Role |
| --- | --- |
| `oauth.lua`, `session.lua`, `account.lua` | OAuth 2.0 public client `programavimas-nvim`: metadata checked against the server, PKCE through a one-shot loopback listener on `127.0.0.1` (any port, RFC 8252), or the device grant; refresh-token rotation under a lock file so several Neovims share one session; revocation on sign-out |
| `http.lua`, `api.lua` | `curl` with its configuration on stdin; `/api/v1` with one refresh and retry on 401 under the same `Idempotency-Key`; RFC 9457 refusals |
| `paths.lua`, `solutions.lua` | The VS Code extension's folder layout and `.programavimas` marker, byte for byte. `slug_table.lua` is generated (`scripts/slug-table.ts`) because Lua has no Unicode normalisation; `test/fixtures/slug-vectors.json` comes from the extension's own `slug`, and a test fails when the two disagree |
| `judge.lua`, `results.lua`, `diff.lua` | Runs and submissions. Neovim has no TLS sockets, so instead of the realtime service it reads the run (`GET /runs/{id}`, `GET /submissions/{id}`) at most once a second until it ends |
| `courses.lua`, `statement.lua`, `ui.lua` | The sidebar, the picker (`vim.ui.select`, so Telescope, fzf-lua or snacks show it when they replace it), the statement (the API's `statementMarkdown`), glyphs and highlight groups |
| `i18n.lua`, `time.lua` | Lithuanian and English with the extension's wording; dates in Lithuanian time |

Design: native Neovim throughout (buffers, splits, `vim.ui.select`, `vim.notify`,
diagnostics, highlight links), and the web app's state glyphs and words as plain characters,
so it works in any terminal and colour scheme without a Nerd Font.
