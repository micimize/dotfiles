# env.nu -- loaded first, before config.nu

# Fedora Atomic /var/home symlink workaround (see scripts/fix-atomic-home.nu)
use ($nu.default-config-dir | path join "scripts/fix-atomic-home.nu") fix-cwd
fix-cwd

# Core environment
$env.EDITOR = "nvim"
$env.VISUAL = "nvim"
$env.PAGER = "less"
$env.LESS = "-R"

# XDG
$env.XDG_CONFIG_HOME = ($env.HOME | path join ".config")

# PATH management
use std/util "path add"
path add "~/.local/bin"
path add "~/.cargo/bin"
path add "/opt/local/bin"
path add "/home/linuxbrew/.linuxbrew/bin"
# lace-into and lace-discover live in lace repo bin/
path add "/var/home/mjr/code/weft/lace/main/bin"

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

# Hostname (cached for prompt/scripts -- avoids calling external command on every use)
$env._HOSTNAME = (^hostname | str trim)

# Starship
$env.STARSHIP_SHELL = "nu"

# Carapace (if installed)
if (which carapace | is-not-empty) {
  $env.CARAPACE_BRIDGES = "zsh,fish,bash,inshellisense"
  $env.CARAPACE_LENIENT = 1
}

# Direnv: silence verbose output (remove this line to see direnv messages)
$env.DIRENV_LOG_FORMAT = ""

# Tool init script generation with freshness caching.
# Generated scripts go to scripts/generated/ under the config dir, then are sourced
# from config.nu. Note: `def` in env.nu is not callable from the same file (nushell
# evaluates env.nu in a special scope), so the cache logic is inlined per tool.

const _generated_dir = ($nu.default-config-dir | path join "scripts/generated")

# Starship init (cached with freshness check, sourced from config.nu)
if (which starship | is-not-empty) {
  let cache = ($_generated_dir | path join "starship.nu")
  let bin = (which starship | first | get path)
  let needs_regen = if ($cache | path exists) {
    (ls $bin | first | get modified) > (ls $cache | first | get modified)
  } else { true }
  if $needs_regen {
    mkdir $_generated_dir
    starship init nu | save -f $cache
  }
}

# Zoxide init (cached with freshness check, sourced from config.nu)
# Placed after fix-cwd so zoxide sees /home/ not /var/home/ paths
if (which zoxide | is-not-empty) {
  let cache = ($_generated_dir | path join "zoxide.nu")
  let bin = (which zoxide | first | get path)
  let needs_regen = if ($cache | path exists) {
    (ls $bin | first | get modified) > (ls $cache | first | get modified)
  } else { true }
  if $needs_regen {
    mkdir $_generated_dir
    zoxide init nushell | save -f $cache
  }
}
