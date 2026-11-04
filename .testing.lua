-- .testing.lua -- configuration of testing.nvim for this project.
-- Written by `testing migrate`; edit freely (it is never overwritten). Every key is optional; the
-- keys are documented in testing.nvim's docs/CONFIG.md. Loading this file executes it (same trust
-- as running the specs).
return {
  -- Lua module root of the project.
  plugin = "github_stats",
  -- How the spec files are run: "auto" = sniffed per file, "h" = on the project's own TESTS/harness.lua,
  -- "script" = a self-running script in its own process.
  dialect = "auto",
  -- Dependencies (directory names) put on the runtimepath: $<NAME>_DIR, .deps/<name>, ../<name>,
  -- stdpath('data')/lazy/<name>.
  deps = { "lib.nvim", "ui.nvim" },
  -- "none" = all specs in one nvim, "file" = one nvim per spec file
  -- (nothing leaks from one file into the next). Needed: specs call setup() and fill module
  -- caches, which must not carry over from one file into the next.
  isolated = "file",
  -- "c" = child started from a -c command (v:vim_did_enter is 0, <cword> works),
  -- "l" = `nvim -l`.
  host = "c",
  -- The old runner let a case without an assertion pass. Two cases are exactly that:
  -- dashboard_spec.lua:15 ("initializes with default values") and
  -- integration/dashboard_flow_spec.lua:22 ("opens, navigates, and closes successfully").
  -- The specs stay unchanged, so these are reported (warn) instead of failing.
  assertions = "warn",
  -- Guards (safety nets, see testing.nvim's docs/GUARDS.md). The suite is clean for all of them
  -- except `state`, hence error everywhere else.
  guards = {
    -- No spec writes outside its sandbox.
    fs = "error",
    -- The suite leaves no state behind: every spec wipes the buffers it creates and restores the
    -- globals it changes. What remains is library state a dependency sets up once and keeps on
    -- purpose, the same in a real session:
    state = {
      mode = "error",
      -- ui.nvim defines its Kit* highlight groups the first time a float is shown (bindings_spec).
      ignore_highlights = { "Kit" },
    },
    -- A scheduled callback that throws after its case ended is a real failure.
    scheduled_error = "error",
    -- A blocking prompt (getchar/input) in a headless run would hang; none occurs.
    prompt = "error",
    -- No spec calls a deprecated API.
    deprecation = "error",
    -- No spec starts an external process or opens a socket (the specs stub the GitHub client).
    process_net = "error",
  },
  -- What the guards let through on purpose.
  guard_allow = {
    spawn = {
      -- :checkhealth github_stats probes `curl --version` (health_spec runs that check).
      "curl",
      -- The statusline reads the repository slug with `git remote get-url origin`
      -- (read-only, local; statusline_spec runs it against the repo and temp dirs).
      "git",
    },
  },
  -- The runner counts which commands, keymaps and autocommands the specs exercise (docs/SURFACE.md of testing.nvim);
  -- `scripts/test.sh surface` compares that with surface.baseline.json (a regression gate, not a percentage).
  surface = { track = true },
  -- Findings the minimal conformance editor cannot avoid (docs/CONFORMANCE.md of testing.nvim); reviewed 2026-10-14.
  conformance = {
    -- gated: a failed check makes `scripts/test.sh conformance` exit 1
    gate = true,
    waivers = {
      {
        check = "K6",
        level = "error",
        text = "GITHUB_TOKEN",
        reason = "every API call needs a token; the conformance run has no secret by design",
        expires = "2027-04-14",
      },
      {
        check = "K6",
        level = "warn",
        text = "Skipping API test",
        reason = "follows from the missing GITHUB_TOKEN (waived above); the conformance run has no secret by design",
        expires = "2027-04-14",
      },
    },
  },
}
