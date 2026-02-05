# login.nu -- only runs when nushell is a login shell

# Auto-start tmux (mirrors bash behavior)
# Uncomment if tmux auto-attach is desired:
# if ($env.TMUX? | is-empty) and ($env.TERM? | default "" | str contains "tmux" | not $in) {
#   ^tmux
# }
