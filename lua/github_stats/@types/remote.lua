---@module 'github_stats.@types.remote'
---@meta

-- github_stats/remote/init.lua
---@alias GHStats.StorageMode "remote"|"local"

---@alias GHStats.StorageStatus "local"|"ready"|"clone"|"unset"

---What `setup()` takes as `storage`: the mode alone, or a table.
---@class GHStats.StorageOptions
---@field mode? GHStats.StorageMode
---@field repo? string "owner/name" of the data repository
---@field dir? string Where it is cloned (default: `stdpath("data")/github_stats.nvim-vault`)
---@field pull_interval_minutes? integer How often a running editor pulls (default 60)

---The resolved storage of this session.
---@class GHStats.Storage
---@field mode GHStats.StorageMode
---@field repo string|nil
---@field dir string
---@field pull_interval_minutes integer
---@field explicit_mode boolean The mode came from `setup()`
---@field deferred boolean The user chose "later" in the guide: it does not open by itself again

---What the state file keeps for this machine.
---@class GHStats.StorageState
---@field mode? GHStats.StorageMode
---@field repo? string
---@field dir? string
---@field deferred? boolean

-- github_stats/remote/proc.lua
---@class GHStats.Remote.ProcResult
---@field ok boolean exit code 0 and not killed
---@field code integer
---@field stdout string
---@field stderr string

---@class GHStats.Remote.ProcOpts
---@field cwd? string
---@field input? string standard input (a secret goes here, never on the command line)
---@field env? table<string, string>
---@field timeout_ms? integer default 120000

-- github_stats/remote/create.lua
---@class GHStats.Remote.ScaffoldOpts
---@field repo string "owner/name"
---@field seed_dir? string A local history to take over (its config.json, data/ and the rest)
---@field plugin_ref? string Branch of github_stats.nvim the workflow uses (default "main")
---@field lib_ref? string Branch of lib.nvim (default "main")

---@class GHStats.Remote.CreateOpts : GHStats.Remote.ScaffoldOpts
---@field dir string Where the clone lives on this machine (must not exist yet, or be empty)
