# env.nu -- loaded first, before config.nu

# Core environment
$env.EDITOR = "nvim"
$env.VISUAL = "nvim"
$env.PAGER = "less"
$env.LESS = "-R"
$env.LANG = ($env.LANG? | default "en_US.UTF-8")

# XDG
$env.XDG_CONFIG_HOME = ($env.HOME | path join ".config")

# PATH management
use std/util "path add"
path add "~/.local/bin"
path add "~/.cargo/bin"
path add "/opt/local/bin"

# FZF solarized dark (still used for ad-hoc fzf invocations)
$env.FZF_DEFAULT_OPTS = ([
  "--color=bg+:#073642,bg:#002b36,spinner:#2aa198,hl:#268bd2"
  "--color=fg:#839496,header:#268bd2,info:#b58900,pointer:#2aa198"
  "--color=marker:#2aa198,fg+:#eee8d5,prompt:#b58900,hl+:#268bd2"
] | str join " ")

# LESS colors (man page highlighting)
# NOTE: These use ansi escape to produce CSI sequences (\e[...).
# Verify during implementation that the escape codes render correctly in `man`.
$env.LESS_TERMCAP_mb = $"(ansi escape)[01;31m"
$env.LESS_TERMCAP_md = $"(ansi escape)[01;31m"
$env.LESS_TERMCAP_me = $"(ansi escape)[0m"
$env.LESS_TERMCAP_se = $"(ansi escape)[0m"
$env.LESS_TERMCAP_so = $"(ansi escape)[01;44;33m"
$env.LESS_TERMCAP_ue = $"(ansi escape)[0m"
$env.LESS_TERMCAP_us = $"(ansi escape)[01;32m"

# Hostname (cached for use in pre_execution hook -- avoids calling sys host on every command)
$env._HOSTNAME = (sys host | get hostname)

# Starship
$env.STARSHIP_SHELL = "nu"

# Carapace (if installed)
if (which carapace | is-not-empty) {
  $env.CARAPACE_BRIDGES = "zsh,fish,bash,inshellisense"
  mkdir ~/.cache/carapace
  carapace _carapace nushell | save -f ~/.cache/carapace/init.nu
}

# Starship init (generates vendor autoload file)
if (which starship | is-not-empty) {
  mkdir ($nu.data-dir | path join "vendor/autoload")
  starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")
}
