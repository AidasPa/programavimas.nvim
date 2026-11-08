local paths = require("programavimas.paths")

local fixtures = vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "fixtures")
local vectors = vim.json.decode(table.concat(vim.fn.readfile(fixtures .. "/slug-vectors.json"), "\n"))

describe("paths", function()
  it("names folders exactly as the VS Code extension does", function()
    for _, vector in ipairs(vectors) do
      eq(vector.slug, paths.slug(vector.title), vector.title)
      eq(vector.positioned, paths.positioned(7, vector.title), vector.title)
      eq(vector.suffixed, paths.with_id_suffix(paths.slug(vector.title), "019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5b"), vector.title)
    end
  end)

  it("lays out course, topic and problem folders with two-digit positions", function()
    eq({ "algoritmai", "03-paieska", "12-dvejetaine-paieska" }, paths.problem_segments({
      course = { title = "Algoritmai" },
      topic = { position = 3, title = "Paieška" },
      problem = { position = 12, title = "Dvejetainė paieška" },
    }))
    eq({ "algoritmai", "01-pirma" }, paths.problem_segments({
      course = { title = "Algoritmai" },
      problem = { position = 1, title = "Pirma" },
    }))
    eq("100-x", paths.positioned(100, "x"))
  end)

  it("creates only plain, safe file names for file I/O", function()
    eq("duom.txt", paths.custom_input_name({ kind = "files", input = "duom.txt", output = "rez.txt" }))
    eq("input.txt", paths.custom_input_name({ kind = "stdio" }))
    for _, bad in ipairs({ "../x", ".programavimas", "main.cpp", "con.txt", "a b.txt", ".hidden", ("a"):rep(65) }) do
      eq(false, paths.is_safe_file_name(bad), bad)
    end
    eq("input.txt", paths.custom_input_name({ kind = "files", input = "../etc/passwd", output = "x" }))
  end)

  it("chooses the last language of the course, then the preference, then the first", function()
    eq("python", paths.choose_language({ "cpp", "python" }, "python", "cpp"))
    eq("cpp", paths.choose_language({ "cpp", "python" }, "csharp", "cpp"))
    eq("python", paths.choose_language({ "python" }, nil, nil))
    eq(nil, paths.choose_language({}, nil, nil))
  end)

  it("writes the marker as the extension does and reads it back", function()
    local marker = {
      v = 1,
      server = "https://beta.programavimas.xyz",
      courseId = "019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5b",
      topicId = nil,
      problemId = "019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5c",
      language = "cpp",
    }
    local text = paths.encode_marker(marker)
    eq(table.concat({
      "{",
      '  "v": 1,',
      '  "server": "https://beta.programavimas.xyz",',
      '  "courseId": "019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5b",',
      '  "topicId": null,',
      '  "problemId": "019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5c",',
      '  "language": "cpp"',
      "}",
      "",
    }, "\n"), text)
    eq(marker, paths.parse_marker(text))
    eq(nil, paths.parse_marker('{"v":2}'))
    eq(nil, paths.parse_marker("not json"))
    eq(nil, paths.parse_marker(text:gsub('"cpp"', '"rust"')))
  end)

  it("starts a new file from the newest of the server draft and the latest submission", function()
    local candidates = {
      drafts = {
        { language = "cpp", code = "draft cpp", savedAt = "2026-11-07T10:00:00.000Z" },
        { language = "python", code = "draft py", savedAt = "2026-11-07T12:00:00.000Z" },
      },
      latest = { language = "cpp", source = "submitted", submittedAt = "2026-11-07T11:00:00.000Z" },
    }
    eq({ language = "python", source = "draft py", origin = "draft" }, paths.start_content(candidates, { "cpp", "python" }, nil))
    eq({ language = "cpp", source = "submitted", origin = "submission" }, paths.start_content(candidates, { "cpp", "python" }, "cpp"))
    eq({ language = "cpp", source = "submitted", origin = "submission" }, paths.start_content(candidates, { "cpp" }, nil))
    eq(nil, paths.start_content({ drafts = { { language = "cpp", code = "  \n", savedAt = "2026-11-07T10:00:00Z" } } }, { "cpp" }, nil))
    eq(nil, paths.start_content({ drafts = {} }, { "cpp" }, nil))
  end)
end)
