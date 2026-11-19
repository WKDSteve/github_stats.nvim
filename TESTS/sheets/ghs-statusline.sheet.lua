-- Feature sheet: the statusline component shows this week's views of the repository the current file belongs to.
-- The repository is a local git repository whose `origin` names github.com/me/proj (git runs for real; nothing is
-- fetched); a file outside any repository shows nothing.
return {
  id = "ghs.statusline",
  feature = "github_stats.statusline",
  title = "The statusline shows this week's views of the file's repository",
  sizes = { { rows = 24, cols = 100 } },
  steps = {
    {
      lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()
        local days = {}
        for d = 3, 1, -1 do
          days[#days + 1] = { timestamp = os.date("!%Y-%m-%d", os.time() - d * 86400) .. "T00:00:00Z", count = 7, uniques = 1 }
        end
        require("github_stats.storage").write_metric("me/proj", "views", { views = days })
        _G.repo = vim.fn.tempname(); vim.fn.mkdir(_G.repo, "p")
        _G.git(_G.repo, { "init", "--quiet" })
        _G.git(_G.repo, { "remote", "add", "origin", "https://github.com/me/proj.git" })
        vim.fn.writefile({ "hello" }, _G.repo .. "/README.md")
        _G.loose = vim.fn.tempname(); vim.fn.mkdir(_G.loose, "p"); vim.fn.writefile({ "x" }, _G.loose .. "/note.txt")]],
      note = "a clone of me/proj with three days of views this week, and a folder outside any repository",
    },
    {
      lua = [[vim.o.laststatus = 2
        vim.o.statusline = "%f%=%{v:lua.require'github_stats.statusline'.status()}"]],
      note = "the native statusline wired as docs/statusline.md shows",
    },
    { lua = [[vim.cmd.edit(vim.fn.fnameescape(_G.repo .. "/README.md"))]] },
    {
      wait = [[vim.api.nvim_eval_statusline(vim.o.statusline, {}).str:find("21 views this week", 1, true)]],
      note = "a file of the repository shows its views (3 x 7)",
    },
    { lua = [[vim.cmd.edit(vim.fn.fnameescape(_G.loose .. "/note.txt"))]] },
    {
      expect = [[not vim.api.nvim_eval_statusline(vim.o.statusline, {}).str:find("views this week", 1, true)]],
      note = "a file outside any repository shows nothing",
    },
  },
}
