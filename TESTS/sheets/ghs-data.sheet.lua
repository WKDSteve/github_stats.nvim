-- Live check: `:GithubStats export` on stored data (digest, compact and debug have feature sheets of their own:
-- ghs-digest, ghs-retention, ghs-diagnostics).
return {
  id = "ghs.data",
  feature = "github_stats.export",
  title = ":GithubStats export to CSV and Markdown",
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
  },
  manual = {
    ":GithubStats export me/proj both <file>.pdf writes a PDF where a converter is installed (pandoc/wkhtmltopdf)",
  },
}
