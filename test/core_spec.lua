local config = require("programavimas.config")
local diff = require("programavimas.diff")
local http = require("programavimas.http")
local i18n = require("programavimas.i18n")
local oauth = require("programavimas.oauth")
local time = require("programavimas.time")

describe("config", function()
  it("sends tokens only over https, or http on this computer", function()
    eq("https://beta.programavimas.xyz", config.origin_of("https://beta.programavimas.xyz/some/path"))
    eq("https://example.com", config.origin_of("https://EXAMPLE.com:443"))
    eq("http://localhost:3000", config.origin_of("http://localhost:3000"))
    eq("http://[::1]:3000", config.origin_of("http://[::1]:3000/"))
    eq(nil, config.origin_of("http://example.com"))
    eq(nil, config.origin_of("https://user@example.com"))
    eq(nil, config.origin_of("ftp://example.com"))
    eq(nil, config.origin_of(nil))
  end)
end)

describe("time", function()
  it("reads RFC 3339 timestamps", function()
    eq(0, time.parse("1970-01-01T00:00:00Z"))
    eq(1793440800, time.parse("2026-10-31T10:00:00.000Z"))
    eq(1793440800, time.parse("2026-10-31T12:00:00+02:00"))
    eq(1793440800.5, time.parse("2026-10-31T10:00:00.500Z"))
    eq(nil, time.parse("yesterday"))
  end)

  it("shows Lithuanian time, summer and winter", function()
    eq("2026-11-07 12:00", time.date_time(time.parse("2026-11-07T10:00:00Z")))
    eq("2026-07-01 13:00", time.date_time(time.parse("2026-07-01T10:00:00Z")))
    -- 2026's changes: Sunday 29 March and Sunday 25 October, at 01:00 UTC.
    eq("02:59", time.clock(time.parse("2026-03-29T00:59:00Z")))
    eq("04:00", time.clock(time.parse("2026-03-29T01:00:00Z")))
    eq("03:59", time.clock(time.parse("2026-10-25T00:59:00Z")))
    eq("03:00", time.clock(time.parse("2026-10-25T01:00:00Z")))
  end)

  -- Saturday 7 November 2026, 12:00 in Vilnius.
  local now = time.parse("2026-11-07T10:00:00Z")
  local function due(at) return time.due(time.parse(at), now) end

  it("says when a deadline is as the web does, by Vilnius calendar days", function()
    eq({ text = "Today, 23:59", date = "Nov 7", tone = "warning" }, due("2026-11-07T21:59:00Z"))
    eq({ text = "Tomorrow, 08:00", date = "Nov 8, 08:00", tone = "warning" }, due("2026-11-08T06:00:00Z"))
    -- 00:30 in Vilnius is already tomorrow, though under a day away.
    eq("Tomorrow, 00:30", due("2026-11-07T22:30:00Z").text)
    eq({ text = "In 5 days", date = "Nov 12", later = "in 5 days", tone = "warning" }, due("2026-11-12T21:59:00Z"))
    eq({ text = "In 7 days", date = "Nov 14", later = "in 7 days", tone = "warning" }, due("2026-11-14T21:59:00Z"))
    eq({ text = "Nov 15", date = "Nov 15", later = "in 8 days" }, due("2026-11-15T21:59:00Z"))
    eq({ text = "Overdue · Nov 6", date = "Nov 6", tone = "danger" }, due("2026-11-06T21:59:00Z"))
  end)

  it("says how far off a later deadline is: days, then weeks, then months", function()
    eq("in 13 days", due("2026-11-20T21:59:00Z").later)
    eq("in 2 weeks", due("2026-11-21T21:59:00Z").later)
    eq("in 3 weeks", due("2026-12-01T21:59:00Z").later)
    eq("in 8 weeks", due("2027-01-05T21:59:00Z").later)
    eq("in 2 months", due("2027-01-06T21:59:00Z").later)
    eq("in 1 month", i18n.t("due.laterMonths", { count = 1 }))
  end)

  it("writes the year only when it isn't this year's, the time only when it isn't 23:59", function()
    eq("Jan 6, 2027", due("2027-01-06T21:59:00Z").date)
    eq("Dec 1", due("2026-12-01T21:59:00Z").date)
    eq("Dec 1, 08:00", due("2026-12-01T06:00:00Z").date)
  end)

  it("says it in Lithuanian, with its plural forms", function()
    config.setup({ language = "lt" })
    local ok, err = pcall(function()
      eq({ text = "Rytoj, 08:00", date = "lapkričio 8 d. 08:00", tone = "warning" }, due("2026-11-08T06:00:00Z"))
      eq({ text = "Po 5 dienų", date = "lapkričio 12 d.", later = "po 5 dienų", tone = "warning" }, due("2026-11-12T21:59:00Z"))
      eq({ text = "gruodžio 1 d.", date = "gruodžio 1 d.", later = "po 3 savaičių" }, due("2026-12-01T21:59:00Z"))
      eq("Pavėluota · lapkričio 6 d.", due("2026-11-06T21:59:00Z").text)
      eq("Šiandien, 23:59", due("2026-11-07T21:59:00Z").text)
      eq("2027 m. sausio 6 d.", due("2027-01-06T21:59:00Z").date)
      eq("po 2 mėnesių", due("2027-01-06T21:59:00Z").later)
      local function form(key, count) return i18n.t(key, { count = count }) end
      eq("Po 1 dienos", form("due.inDays", 1))
      eq("Po 2 dienų", form("due.inDays", 2))
      eq("po 1 savaitės", form("due.laterWeeks", 1))
      eq("po 4 savaičių", form("due.laterWeeks", 4))
      eq("po 10 savaičių", form("due.laterWeeks", 10))
      eq("po 11 savaičių", form("due.laterWeeks", 11))
      eq("po 21 savaitės", form("due.laterWeeks", 21))
      eq("po 22 savaičių", form("due.laterWeeks", 22))
      eq("po 1 mėnesio", form("due.laterMonths", 1))
      eq("po 12 mėnesių", form("due.laterMonths", 12))
    end)
    config.setup({ language = "en" })
    if not ok then error(err, 0) end
  end)

  it("tells a message's values from its words", function()
    eq({
      { text = "Liko ", value = false },
      { text = "3", value = true },
      { text = " iš ", value = false },
      { text = "5", value = true },
    }, (function()
      config.setup({ language = "lt" })
      local parts = i18n.parts("statement.attempts", { left = 3, total = 5 })
      config.setup({ language = "en" })
      return parts
    end)())
    eq("{left} of 5 left", i18n.t("statement.attempts", { total = 5 }))
  end)
end)

describe("diff", function()
  it("marks differing lines, ignoring trailing spaces and one final newline", function()
    local marks = diff.compare("1\n2 \n3\n", "1\n2\n4")
    eq({ false, false, true }, marks.expected)
    eq({ false, false, true }, marks.actual)
    eq({ line = 3, expected = "3", actual = "4" }, marks.first)
    eq({ line = 2, expected = "2", actual = nil }, diff.compare("1\n2", "1").first)
    eq(nil, diff.compare("a\r\nb\r\n", "a\nb").first)
  end)
end)

describe("oauth", function()
  it("computes the PKCE S256 challenge (base64url of the SHA-256, as openssl computes it)", function()
    -- printf %s <verifier> | openssl dgst -sha256 -binary | base64 | tr '+/' '-_' | tr -d '='
    eq("OFLfZUOT86t8QrmM5vPbArEGYugVd74GgEFc8FFlfH8", oauth.challenge("dBjftJeZ4CVP-mJ92K9dZtiTUEeOcF9AGF7y8pM2Exk"))
    eq(43, #oauth.random(32))
  end)

  it("accepts only metadata of the configured server", function()
    local origin = "https://beta.programavimas.xyz"
    local meta = {
      issuer = origin,
      authorization_endpoint = origin .. "/oauth/authorize",
      token_endpoint = origin .. "/oauth/token",
      revocation_endpoint = origin .. "/oauth/revoke",
      device_authorization_endpoint = origin .. "/oauth/device_authorization",
      code_challenge_methods_supported = { "S256" },
    }
    eq(nil, oauth.metadata_problem(meta, origin))
    eq("issuer", oauth.metadata_problem(vim.tbl_extend("force", meta, { issuer = "https://evil.example" }), origin))
    eq("token_endpoint", oauth.metadata_problem(vim.tbl_extend("force", meta, { token_endpoint = "https://beta.programavimas.xyz.evil.example/t" }), origin))
    eq("pkce", oauth.metadata_problem(vim.tbl_extend("force", meta, { code_challenge_methods_supported = { "plain" } }), origin))
  end)
end)

describe("http", function()
  it("encodes forms and reads queries", function()
    eq("a=1%202&b=%C4%85%2B%2F", http.form({ b = "ą+/", a = "1 2" }))
    eq({ code = "x y", state = "ą" }, http.parse_query("code=x+y&state=%C4%85"))
  end)
end)
