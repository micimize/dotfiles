# Hooks module
# The hand-rolled ~/.full_history pre_execution hook has been removed.
# Nushell's built-in SQLite history (config.history.file_format = "sqlite")
# already stores timestamps, hostname, CWD, exit codes, duration, and session IDs.
# Use `history --long | where cwd =~ "project"` for structured history queries.
