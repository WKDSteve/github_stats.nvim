-- Feature sheet: `:GithubStats digest` writes the per-repository digest other programs read.
return {
  id = "ghs.digest",
  feature = "github_stats.digest",
  title = ":GithubStats digest writes the digest of the tracked repository",
  sizes = { { rows = 30, cols = 110 } },
  steps = {
    { lua = [[dofile(vim.fn.getcwd() .. "/TESTS/sheets/_helpers.lua"); _G.boot()]] },
    { keys = ":GithubStats digest<CR>" },
    {
      wait = [[_G.noted("Digest: 1 written, 0 unchanged, 0 without history") and not _G.noted("Digest error")]],
      note = "digest writes the one repository's digest, without an error",
    },
    { lua = [[_G.forget()]] },
    { keys = ":GithubStats digest<CR>", note = "again, with nothing new" },
    { wait = [[_G.noted("Digest: 0 written, 1 unchanged")]], note = "the digest is left as it is" },
  },
}
