# GitHub traffic history

The data store of [github_stats.nvim]({{PLUGIN_HOME}}): the GitHub traffic (clones, views,
referrers, paths) of the repositories in `config.json`, collected once a day by the workflow in
`.github/workflows/collect.yml` and committed here.

Every Neovim that uses this repository only clones and pulls it, so you get the same history on
every machine and nothing is fetched twice. GitHub keeps traffic for 14 days only; the workflow
also runs on days no editor is open, so no window is lost.

## What it needs

- The secret `GH_STATS_TOKEN`: a token that can read the traffic of the tracked repositories
  (classic token: scope `repo`; fine-grained token: "Administration: read" on those repositories).

  ```sh
  gh secret set GH_STATS_TOKEN -R {{REPO}}
  ```

  `:GithubStats setup` in Neovim offers to do this for you.

## Day to day

- Change what is tracked: edit `config.json` (in Neovim: the clone this plugin uses), then
  `:GithubStats sync` commits and pushes it.
- Collect now instead of tomorrow: `:GithubStats fetch` starts the workflow
  (or `gh workflow run collect.yml -R {{REPO}}`).
- The layout of `data/` is the plugin's storage format, written by the plugin only.
