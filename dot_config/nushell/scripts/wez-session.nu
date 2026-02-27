# WezTerm session persistence commands
# Uses OSC 1337 SetUserVar to communicate with WezTerm's resurrect plugin.
# IPC protocol: "action|arg|nonce" — nonce ensures user-var-changed fires
# even for repeated identical commands. WezTerm Lua strips the nonce.
# Helper functions (wez-ipc, wez-list-sessions) are non-exported; they are
# accessible in config.nu because we use `source` (not `use`). If migrating
# to `use`, these must be exported or the auto-trigger refactored.

const WEZ_SESSION_DIR = "~/.local/share/wezterm/resurrect/workspace"

# Send a command to WezTerm via OSC 1337 user variable IPC
def wez-ipc [action: string, arg?: string] {
  if ($env.TERM_PROGRAM? | default "") != "WezTerm" {
    error make { msg: "wez commands only work inside WezTerm" }
  }
  let nonce = (random chars -l 8)
  let payload = ([$action, ($arg | default ""), $nonce] | str join "|")
  let encoded = ($payload | encode base64)
  print -n $"\u{1b}]1337;SetUserVar=WEZ_SESSION_CMD=($encoded)\u{07}"
}

# List saved session names from disk (no IPC needed)
def wez-list-sessions [] {
  let dir = ($WEZ_SESSION_DIR | path expand)
  if not ($dir | path exists) { return [] }
  ls $dir
    | where name =~ '\.json$'
    | get name
    | each { |f| $f | path parse | get stem }
}

# Save the current workspace session
export def "wez save" [
  name?: string  # Session name (defaults to current workspace name)
] {
  wez-ipc "save" $name
}

# Restore a saved session (interactive picker if no name given)
export def "wez restore" [
  name?: string  # Session name to restore
] {
  let target = if ($name | is-not-empty) {
    $name
  } else {
    let sessions = (wez-list-sessions)
    if ($sessions | is-empty) {
      print "No saved sessions found."
      return
    }
    let choice = ($sessions | input list "Select session to restore:")
    if ($choice | is-empty) {
      print "Cancelled."
      return
    }
    $choice
  }
  wez-ipc "restore" $target
}

# List saved sessions
export def "wez list" [] {
  let sessions = (wez-list-sessions)
  if ($sessions | is-empty) {
    print "No saved sessions."
    return
  }
  let dir = ($WEZ_SESSION_DIR | path expand)
  ls $dir
    | where name =~ '\.json$'
    | select name modified
    | update name { path parse | get stem }
    | rename session modified
    | sort-by modified -r
}

# Delete a saved session
export def "wez delete" [
  name: string  # Session name to delete
] {
  let file = ([$WEZ_SESSION_DIR, $"($name).json"] | path join | path expand)
  if ($file | path exists) {
    rm $file
    print $"Deleted session: ($name)"
  } else {
    print $"Session not found: ($name)"
  }
}
