# config.nu -- loaded after env.nu

# ── Disable banner ──
$env.config.show_banner = false

# ── Editor ──
$env.config.buffer_editor = "nvim"

# ── Vi mode ──
$env.config.edit_mode = "vi"
$env.config.cursor_shape = {
  vi_insert: line
  vi_normal: block
  emacs: line
}

# ── History (SQLite, 1M entries, shared across sessions) ──
$env.config.history.file_format = "sqlite"
$env.config.history.max_size = 1_000_000
$env.config.history.sync_on_enter = true
$env.config.history.isolation = false

# ── Completions ──
$env.config.completions.case_sensitive = false
$env.config.completions.quick = true
$env.config.completions.partial = true
$env.config.completions.algorithm = "fuzzy"
$env.config.completions.use_ls_colors = true

# ── Prompt indicators (starship handles the main prompt) ──
$env.PROMPT_INDICATOR_VI_INSERT = ": "
$env.PROMPT_INDICATOR_VI_NORMAL = "> "
$env.PROMPT_MULTILINE_INDICATOR = "::: "

# ── Source modular config scripts ──
# All six scripts must exist (nushell's source is a parse-time keyword).
source ($nu.default-config-dir | path join "scripts/aliases.nu")
source ($nu.default-config-dir | path join "scripts/colors.nu")
source ($nu.default-config-dir | path join "scripts/completions.nu")
source ($nu.default-config-dir | path join "scripts/hooks.nu")
source ($nu.default-config-dir | path join "scripts/keybindings.nu")
source ($nu.default-config-dir | path join "scripts/utils.nu")
