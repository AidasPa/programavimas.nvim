local config = require("programavimas.config")
local diff = require("programavimas.diff")
local http = require("programavimas.http")
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

  it("says when a deadline is", function()
    local now = time.parse("2026-11-07T10:00:00Z")
    eq("Today, 23:59", time.due_label(time.parse("2026-11-07T21:59:00Z"), now))
    eq("Tomorrow, 08:00", time.due_label(time.parse("2026-11-08T06:00:00Z"), now))
    eq("Due 2026-11-12 23:59", time.due_label(time.parse("2026-11-12T21:59:00Z"), now))
    eq("Overdue · 2026-11-06 23:59", time.due_label(time.parse("2026-11-06T21:59:00Z"), now))
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
