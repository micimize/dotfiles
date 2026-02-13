# Hooks module
# The hand-rolled ~/.full_history pre_execution hook has been removed.
# Nushell's built-in SQLite history (config.history.file_format = "sqlite")
# already stores timestamps, hostname, CWD, exit codes, duration, and session IDs.
# Use `history --long | where cwd =~ "project"` for structured history queries.

# ── Direnv integration ──
# Per-directory environment management via env_change.PWD hook.
# Reference: https://www.nushell.sh/cookbook/direnv.html
use std/config *

$env.config.hooks.env_change.PWD = ($env.config.hooks.env_change.PWD? | default [])

$env.config.hooks.env_change.PWD ++= [{||
  if (which direnv | is-empty) { return }
  direnv export json | from json | default {} | load-env
  # Direnv may stringify PATH; re-convert to list via standard library helper
  if ($env.PATH | describe | str starts-with "string") {
    $env.PATH = do (env-conversions).path.from_string $env.PATH
  }
}]
