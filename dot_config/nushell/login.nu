# login.nu -- only runs when nushell is a login shell

# Session-wide locale default (belongs in login, not env, since it's a session property)
$env.LANG = ($env.LANG? | default "en_US.UTF-8")

# Auto-start tmux (mirrors bash behavior)
# Uncomment if tmux auto-attach is desired:
# if ($env.TMUX? | is-empty) and ($env.TERM? | default "" | str contains "tmux" | not $in) {
#   ^tmux
# }
