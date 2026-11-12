-- Live check: `:GithubStats export`, `digest`, `compact dry-run` and `debug` on stored data.
return {
  id = "ghs.data",
  feature = "github_stats.export",
  title = ":GithubStats export, digest, compact dry-run and debug",
  task = "github_stats.nvim/testblatt-bindings-checkliste",
  sizes = { { rows = 40, cols = 120 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot(); _G.out = _G.dir .. "/out"]] },
    { lua = [[vim.fn.mkdir(_G.out, "p"); vim.cmd("GithubStats export me/proj clones " .. _G.out .. "/Clones.csv")]] },
    { expect = [[vim.fn.filereadable(_G.out .. "/Clones.csv") == 1]], note = "export writes the CSV" },
    {
      expect = [[table.concat(vim.fn.readfile(_G.out .. "/Clones.csv"), "\n"):find("2026-10-12", 1, true) ~= nil]],
      note = "with the stored days in it",
    },
    { lua = [[vim.cmd("GithubStats export me/proj both " .. _G.out .. "/Both.md")]] },
    { expect = [[vim.fn.filereadable(_G.out .. "/Both.md") == 1]], note = "export both writes the Markdown report" },
    { lua = [[_G.forget(); vim.cmd("GithubStats export me/proj clones " .. _G.out .. "/x.txt")]] },
    { expect = [[_G.noted("File must have .csv, .md or .pdf extension")]], note = "another extension is refused" },
    { lua = [[_G.forget(); vim.cmd("GithubStats digest")]] },
    {
      expect = [[_G.noted("Digest: 1 written, 0 unchanged, 0 without history") and not _G.noted("Digest error")]],
      note = "digest writes the one repository's digest, without an error",
    },
    { lua = [[_G.forget(); vim.cmd("GithubStats compact dry-run")]] },
    {
      expect = [[_G.noted("Dry run: archived ") and _G.noted("would remove") and not _G.noted("Retention error")]],
      note = "compact dry-run only previews the archive, without an error",
    },
    { expect = [[vim.fn.filereadable(_G.out .. "/Clones.csv") == 1]], note = "and the stored files are still there" },
    { lua = [[vim.cmd("GithubStats debug")]] },
    { wait = [[_G.floattext():find("me/proj", 1, true) ~= nil]], note = "debug lists the configured repository" },
  },
  manual = {
    ":GithubStats debug tests the API connection with a real token (GITHUB_TOKEN) -- run it once on a machine with one",
  },
}
